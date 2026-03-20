local cjson = require('cjson.safe')
local runtime = require('config.runtime')
local normalize = require('core.normalize')
local router = require('core.router')
local keypool = require('core.keypool')
local rewrite = require('core.rewrite')
local errors = require('core.errors')
local observe = require('core.observe')
local http_client = require('core.http_client')
local auth = require('core.auth')

local _M = {}

local function safe_json_encode(obj)
  local ok, encoded = pcall(cjson.encode, obj)
  if ok then
    return encoded
  end
  return '{}'
end

local function format_timestamp()
  local now = ngx.now()
  local sec = math.floor(now)
  local msec = math.floor((now - sec) * 1000)
  return os.date('%Y-%m-%d %H:%M:%S', sec) .. string.format('.%03d', msec)
end

local function log_failed_request(provider, url, headers, request_body, res, req_err)
  local log_entry = {
    timestamp = format_timestamp(),
    level = 'ERROR',
    event = 'upstream_request_failed',
    
    -- 请求信息
    request = {
      url = url,
      method = 'POST',
      headers = headers,  -- 完整请求头
      body = request_body,  -- 完整请求体
    },
    
    -- 响应信息
    response = {
      status = res and res.status or nil,
      headers = res and res.headers or nil,
      body = res and res.body or nil,  -- 完整响应体
    },
    
    -- 错误信息
    error = req_err,
    
    -- 上下文
    provider = provider.name,
    key_id = headers and headers['Authorization'] and '***' or nil,  -- 脱敏
    request_id = ngx.ctx.request_id,
  }
  
  ngx.log(ngx.ERR, '[', format_timestamp(), '] ', cjson.encode(log_entry))
end

local function log_upstream_request(provider, url, headers, request_body)
  local log_entry = {
    timestamp = format_timestamp(),
    level = 'INFO',
    event = 'upstream_request',
    request_id = ngx.ctx.request_id,
    provider = provider and provider.name or nil,
    request = {
      url = url,
      method = 'POST',
      headers = headers,
      body = request_body,
    },
  }

  local line = cjson.encode(log_entry)
  if not line then
    return
  end

  local handle, err = io.open('/var/log/llm-gateway/upstream.log', 'a')
  if not handle then
    ngx.log(ngx.WARN, '[openai_compat] failed to open upstream.log: ', err or 'unknown error')
    return
  end
  handle:write(line, '\n')
  handle:close()
end

local hop_by_hop = {
  ['connection'] = true,
  ['keep-alive'] = true,
  ['proxy-authenticate'] = true,
  ['proxy-authorization'] = true,
  ['te'] = true,
  ['trailers'] = true,
  ['transfer-encoding'] = true,
  ['upgrade'] = true,
  ['content-length'] = true,
}

local function read_body()
  ngx.req.read_body()
  local data = ngx.req.get_body_data()
  if data then
    return data
  end
  local path = ngx.req.get_body_file()
  if not path then
    return nil
  end
  local handle = io.open(path, 'rb')
  if not handle then
    return nil
  end
  local content = handle:read('*a')
  handle:close()
  return content
end

local function join_url(base, path)
  if not path or path == '' then
    return base
  end
  local base_tail = base:sub(-1)
  local path_head = path:sub(1, 1)
  if base_tail == '/' and path_head == '/' then
    return base:sub(1, -2) .. path
  end
  if base_tail ~= '/' and path_head ~= '/' then
    return base .. '/' .. path
  end
  return base .. path
end

local function build_headers(provider, key, request_id)
  local auth = provider.auth or {}
  local header_name = auth.header or 'Authorization'
  local prefix = auth.prefix or ''

  local headers = {
    ['Content-Type'] = 'application/json',
    ['Accept'] = 'application/json',
    ['Accept-Encoding'] = 'identity',
    ['User-Agent'] = 'llm-gateway-lite/0.1',
    ['X-Request-Id'] = request_id,
    ['Host'] = provider.host_header,
  }

  headers[header_name] = prefix .. (key.value or '')

  if provider.headers then
    for name, value in pairs(provider.headers) do
      headers[name] = value
    end
  end

  return headers
end

local function copy_response_headers(headers)
  for name, value in pairs(headers or {}) do
    local key = name:lower()
    if not hop_by_hop[key] then
      ngx.header[name] = value
    end
  end
end

local function classify_error(status, err)
  if err then
    return 'upstream_error'
  end
  if not status then
    return 'upstream_error'
  end
  if status == 401 or status == 403 then
    return 'auth'
  end
  if status == 429 then
    return 'rate_limit'
  end
  if status >= 500 then
    return 'upstream_5xx'
  end
  if status >= 400 then
    return 'upstream_4xx'
  end
  return nil
end

local function inject_channel_to_json_response(raw_body, channel)
  if type(raw_body) ~= 'string' or raw_body == '' or not channel or channel == '' then
    return raw_body
  end

  local body_obj = cjson.decode(raw_body)
  if type(body_obj) ~= 'table' then
    return raw_body
  end

  body_obj.channel = channel
  local encoded = cjson.encode(body_obj)
  if not encoded then
    return raw_body
  end
  return encoded
end

local function deep_copy(value)
  if type(value) ~= 'table' then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[k] = deep_copy(v)
  end
  return out
end

local function merge_defaults_into_body(body, defaults)
  for key, default_value in pairs(defaults) do
    if key ~= 'model' then
      local current_value = body[key]
      if current_value == nil then
        body[key] = deep_copy(default_value)
      elseif type(current_value) == 'table' and type(default_value) == 'table' then
        merge_defaults_into_body(current_value, default_value)
      end
    end
  end
end

local function apply_provider_request_defaults(body, provider)
  if type(body) ~= 'table' or type(provider) ~= 'table' then
    return
  end
  local defaults = provider.request_defaults
  if type(defaults) ~= 'table' then
    return
  end
  merge_defaults_into_body(body, defaults)
end

local function extract_error_signal(res)
  if not res or type(res.body) ~= 'string' or res.body == '' then
    return ''
  end

  local decoded = cjson.decode(res.body)
  if type(decoded) ~= 'table' then
    return string.lower(res.body)
  end

  local parts = {}
  local function push(v)
    if type(v) == 'string' and v ~= '' then
      table.insert(parts, string.lower(v))
    end
  end

  push(decoded.code)
  push(decoded.type)
  push(decoded.message)

  if type(decoded.error) == 'table' then
    push(decoded.error.code)
    push(decoded.error.type)
    push(decoded.error.message)
    push(decoded.error.param)
  elseif type(decoded.error) == 'string' then
    push(decoded.error)
  end

  if type(decoded.detail) == 'string' then
    push(decoded.detail)
  end

  return table.concat(parts, ' ')
end

local function should_cooldown_key(status, res, err)
  if err then
    return false
  end
  if not status then
    return false
  end
  if status == 401 or status == 402 or status == 403 or status == 429 then
    return true
  end
  if status ~= 400 then
    return false
  end

  local signal = extract_error_signal(res)
  if signal == '' then
    return false
  end

  local patterns = {
    'insufficient_quota',
    'rate limit',
    'too many requests',
    'quota exceeded',
    'exceeded your current quota',
    'billing',
    'credit',
    'invalid api key',
    'api key',
    'authentication',
    'unauthorized',
    'token',
    '限流',
    '配额',
    '超限',
    '余额',
    '欠费',
  }
  for _, pattern in ipairs(patterns) do
    if signal:find(pattern, 1, true) then
      return true
    end
  end

  return false
end

local function should_retry(res, err)
  if err then
    return true
  end
  if not res or not res.status then
    return true
  end
  local status = res.status
  if status == 401 or status == 402 or status == 403 or status == 408 or status == 409 or status == 425 or status == 429 then
    return true
  end
  if status == 400 then
    return should_cooldown_key(status, res, err)
  end
  if status >= 500 and status <= 599 then
    return true
  end
  return false
end

local function do_request(provider, key, endpoint, body_json, request_id)
  local url = join_url(provider.base_url, endpoint)
  if ngx.var.args and ngx.var.args ~= '' then
    url = url .. '?' .. ngx.var.args
  end
  local headers = build_headers(provider, key, request_id)
  return http_client.request({
    url = url,
    method = 'POST',
    headers = headers,
    body = body_json,
    timeout_ms = provider.timeout_ms,
    ssl_verify = provider.ssl_verify,
  })
end

local function relay_stream_response(stream_res)
  if not stream_res then
    return nil, 'missing stream response'
  end

  while true do
    local chunk, chunk_err = stream_res.read_chunk()
    if chunk_err then
      return nil, chunk_err
    end
    if not chunk then
      return true
    end
    local ok, print_err = ngx.print(chunk)
    if not ok then
      return nil, print_err or 'failed to write chunk'
    end
    local ok_flush, flush_err = ngx.flush(true)
    if not ok_flush then
      return nil, flush_err or 'failed to flush chunk'
    end
  end
end

local function pick_retry_target(cfg, std_model, endpoint_key, current_provider, current_model, attempted_keys_by_provider, exhausted_providers)
  local current_attempts = attempted_keys_by_provider[current_provider.name] or {}
  local retry_key = keypool.pick_key(current_provider, { exclude_key_ids = current_attempts })
  if retry_key then
    return current_provider, current_model, retry_key
  end

  exhausted_providers[current_provider.name] = true

  local switches = 0
  while switches < 16 do
    switches = switches + 1
    local alt_provider, alt_model, alt_key = router.select_provider_with_key(cfg, std_model, {
      exclude_providers = exhausted_providers,
      exclude_key_ids_by_provider = attempted_keys_by_provider,
    })
    if not alt_provider then
      return nil, nil, nil
    end
    local endpoint = alt_provider.endpoints and alt_provider.endpoints[endpoint_key] or nil
    if endpoint then
      if alt_key then
        return alt_provider, alt_model, alt_key
      end
    end
    exhausted_providers[alt_provider.name] = true
  end

  return nil, nil, nil
end

function _M.handle(endpoint_key)
  observe.start_request()

  -- 鉴权检查
  local auth_ok, auth_err = auth.validate()
  if not auth_ok then
    ngx.ctx.error_type = 'auth_failed'
    ngx.log(ngx.WARN, '[openai_compat] authentication failed: ', auth_err or 'unknown')
    return errors.send(401, auth_err or 'authentication failed', 'authentication_error')
  end

  local cfg = runtime.get_config()
  if not cfg then
    ngx.ctx.error_type = 'config_error'
    return errors.unavailable('config not loaded')
  end

  local raw_body = read_body()
  if not raw_body or raw_body == '' then
    ngx.ctx.error_type = 'invalid_request'
    return errors.bad_request('missing request body')
  end

  local body, decode_err = cjson.decode(raw_body)
  if not body then
    ngx.ctx.error_type = 'invalid_request'
    return errors.bad_request('invalid json body: ' .. tostring(decode_err))
  end

  local input_model = body.model
  if not input_model or input_model == '' then
    ngx.ctx.error_type = 'invalid_request'
    return errors.bad_request('missing model')
  end

  local requested_provider = nil
  if type(body.provider) == 'string' and body.provider ~= '' then
    requested_provider = body.provider
  end
  body.provider = nil

  local std_model = normalize.to_standard(cfg, input_model)
  if not std_model then
    ngx.ctx.error_type = 'invalid_model'
    return errors.bad_request('unsupported model: ' .. tostring(input_model))
  end

  ngx.ctx.input_model = input_model
  ngx.ctx.std_model = std_model

  local select_opts = {}
  if requested_provider then
    select_opts.prefer_provider = requested_provider
  end

  local provider, provider_model, key, select_err = router.select_provider_with_key(cfg, std_model, select_opts)
  if not provider then
    ngx.ctx.error_type = 'no_provider'
    if select_err == 'no_provider_available' then
      return errors.unavailable('no provider available')
    end
    return errors.unavailable('provider selection failed')
  end

  local endpoint = provider.endpoints and provider.endpoints[endpoint_key] or nil
  if not endpoint then
    ngx.ctx.error_type = 'config_error'
    return errors.unavailable('provider endpoint not configured')
  end

  local stream_body = deep_copy(body)
  apply_provider_request_defaults(stream_body, provider)
  stream_body.model = provider_model
  local body_json, encode_err = rewrite.encode_body(stream_body)
  if not body_json then
    ngx.ctx.error_type = 'invalid_request'
    return errors.bad_request('failed to encode body: ' .. tostring(encode_err))
  end

  local is_stream = body.stream == true
  ngx.ctx.stream = is_stream

  if is_stream then
    local start_time = ngx.now()
    local stream_res, req_err = nil, nil
    local final_provider = provider
    local final_key = key
    local final_model = provider_model
    local final_endpoint = endpoint
    local attempted_keys_by_provider = {}
    local exhausted_providers = {}
    local max_attempts = 16
    local attempt = 0
    local last_res = nil

    while attempt < max_attempts do
      attempt = attempt + 1
      final_provider = provider
      final_key = key
      final_model = provider_model
      final_endpoint = provider.endpoints and provider.endpoints[endpoint_key] or nil

      if not final_endpoint then
        ngx.ctx.error_type = 'config_error'
        return errors.unavailable('provider endpoint not configured')
      end

      attempted_keys_by_provider[provider.name] = attempted_keys_by_provider[provider.name] or {}
      attempted_keys_by_provider[provider.name][key.id] = true

      local attempt_body = deep_copy(body)
      apply_provider_request_defaults(attempt_body, provider)
      attempt_body.model = provider_model
      local encoded, body_err = rewrite.encode_body(attempt_body)
      if not encoded then
        ngx.ctx.error_type = 'invalid_request'
        return errors.bad_request('failed to encode body: ' .. tostring(body_err))
      end
      body_json = encoded

      local url = join_url(provider.base_url, final_endpoint)
      local request_headers = build_headers(provider, key, ngx.ctx.request_id)
      log_upstream_request(provider, url, request_headers, body_json)

      if attempt == 1 then
        ngx.log(ngx.INFO, '[', format_timestamp(), '] [openai_compat] making stream request: provider=', provider.name, ', url=', url, ', model=', provider_model, ', key_id=', key.id, ', ssl_verify=', provider.ssl_verify)
      else
        ngx.log(ngx.INFO, '[', format_timestamp(), '] [openai_compat] retrying stream with provider=', provider.name, ', url=', url, ', key_id=', key.id, ', attempt=', attempt)
      end

      stream_res, req_err = http_client.request_stream({
        url = url,
        method = 'POST',
        headers = request_headers,
        body = body_json,
        timeout_ms = provider.timeout_ms,
        ssl_verify = provider.ssl_verify,
      })

      if not stream_res and req_err then
        ngx.log(ngx.ERR, '[', format_timestamp(), '] [openai_compat] stream request failed: provider=', provider.name, ', url=', url, ', error=', req_err, ', key_id=', key.id)
        log_failed_request(provider, url, request_headers, body_json, nil, req_err)
        last_res = nil
      elseif stream_res and stream_res.status ~= 200 then
        local err_body, read_err = stream_res.read_all(256 * 1024)
        if read_err and read_err ~= 'body exceeds limit' then
          ngx.log(ngx.WARN, '[', format_timestamp(), '] [openai_compat] failed reading stream error body: provider=', provider.name, ', status=', stream_res.status, ', error=', read_err)
        end
        stream_res.close()
        local res_obj = {
          status = stream_res.status,
          headers = stream_res.headers or {},
          body = err_body or '',
        }
        ngx.log(ngx.WARN, '[', format_timestamp(), '] [openai_compat] stream response non-200: provider=', provider.name, ', status=', res_obj.status, ', body_size=', #(res_obj.body or ''))
        log_failed_request(provider, url, request_headers, body_json, res_obj, nil)
        last_res = res_obj
      else
        ngx.log(ngx.INFO, '[', format_timestamp(), '] [openai_compat] stream response ready: provider=', provider.name, ', status=200')
        break
      end

      if not should_retry(last_res, req_err) then
        break
      end

      if should_cooldown_key(last_res and last_res.status or nil, last_res, req_err) then
        keypool.mark_key_cooldown(provider, key.id, runtime.key_cooldown_sec, {
          source = 'stream_retry',
          status = last_res and last_res.status or nil,
        })
      end

      local next_provider, next_model, next_key = pick_retry_target(
        cfg,
        std_model,
        endpoint_key,
        provider,
        provider_model,
        attempted_keys_by_provider,
        exhausted_providers
      )
      if not next_provider then
        break
      end

      provider = next_provider
      provider_model = next_model
      key = next_key
    end

    ngx.ctx.latency_ms = math.floor((ngx.now() - start_time) * 1000)
    ngx.ctx.provider = final_provider.name
    ngx.ctx.provider_model = final_model
    ngx.ctx.key_id = final_key.id

    if not stream_res then
      if not last_res then
        local error_details = {
          provider = final_provider.name,
          url = join_url(final_provider.base_url, final_endpoint or endpoint),
          key_id = final_key.id,
          error = req_err or 'unknown error',
          ssl_verify = final_provider.ssl_verify,
          timeout_ms = final_provider.timeout_ms,
        }
        ngx.log(ngx.ERR, '[', format_timestamp(), '] [openai_compat] stream upstream request failed: ', cjson.encode(error_details))
        ngx.ctx.error_type = 'upstream_error'
        ngx.ctx.error_details = error_details
        return errors.send(502, 'upstream request failed', 'upstream_error')
      end
      ngx.ctx.upstream_status = last_res.status
      ngx.ctx.error_type = classify_error(last_res.status, req_err)
      copy_response_headers(last_res.headers)
      observe.maybe_expose_selection(final_provider, final_key)
      ngx.status = last_res.status
      ngx.say(inject_channel_to_json_response(last_res.body or '', final_provider.name))
      return ngx.exit(last_res.status)
    end

    ngx.ctx.upstream_status = 200
    ngx.ctx.error_type = nil
    copy_response_headers(stream_res.headers)
    ngx.header['X-Accel-Buffering'] = 'no'
    observe.maybe_expose_selection(final_provider, final_key)
    ngx.status = 200
    local relay_ok, relay_err = relay_stream_response(stream_res)
    stream_res.close()
    if not relay_ok then
      ngx.log(ngx.ERR, '[', format_timestamp(), '] [openai_compat] stream relay failed: provider=', final_provider.name, ', key_id=', final_key.id, ', error=', relay_err)
    end
    return ngx.exit(200)
  end

  local start_time = ngx.now()
  local res, req_err = nil, nil
  local final_provider = provider
  local final_key = key
  local final_model = provider_model
  local final_endpoint = endpoint
  local attempted_keys_by_provider = {}
  local exhausted_providers = {}
  local max_attempts = 16
  local attempt = 0

  while attempt < max_attempts do
    attempt = attempt + 1
    final_provider = provider
    final_key = key
    final_model = provider_model
    final_endpoint = provider.endpoints and provider.endpoints[endpoint_key] or nil

    if not final_endpoint then
      ngx.ctx.error_type = 'config_error'
      return errors.unavailable('provider endpoint not configured')
    end

    attempted_keys_by_provider[provider.name] = attempted_keys_by_provider[provider.name] or {}
    attempted_keys_by_provider[provider.name][key.id] = true

    local attempt_body = deep_copy(body)
    apply_provider_request_defaults(attempt_body, provider)
    attempt_body.model = provider_model
    local encoded, body_err = rewrite.encode_body(attempt_body)
    if not encoded then
      ngx.ctx.error_type = 'invalid_request'
      return errors.bad_request('failed to encode body: ' .. tostring(body_err))
    end
    body_json = encoded

    local url = join_url(provider.base_url, final_endpoint)
    local request_headers = build_headers(provider, key, ngx.ctx.request_id)

    if attempt == 1 then
      ngx.log(ngx.INFO, '[', format_timestamp(), '] [openai_compat] making request: provider=', provider.name, ', url=', url, ', model=', provider_model, ', key_id=', key.id, ', ssl_verify=', provider.ssl_verify)
    else
      ngx.log(ngx.INFO, '[', format_timestamp(), '] [openai_compat] retrying with provider=', provider.name, ', url=', url, ', key_id=', key.id, ', attempt=', attempt)
    end
    log_upstream_request(provider, url, request_headers, body_json)
    res, req_err = do_request(provider, key, final_endpoint, body_json, ngx.ctx.request_id)

    if not res and req_err then
      ngx.log(ngx.ERR, '[', format_timestamp(), '] [openai_compat] request failed: provider=', provider.name, ', url=', url, ', error=', req_err, ', key_id=', key.id)
      log_failed_request(provider, url, request_headers, body_json, nil, req_err)
    elseif res and res.status ~= 200 then
      ngx.log(ngx.WARN, '[', format_timestamp(), '] [openai_compat] request response: provider=', provider.name, ', status=', res.status, ', body_size=', #(res.body or ''))
      log_failed_request(provider, url, request_headers, body_json, res, nil)
    elseif res then
      ngx.log(ngx.INFO, '[', format_timestamp(), '] [openai_compat] request response: provider=', provider.name, ', status=', res.status, ', body_size=', #(res.body or ''))
    end

    if not should_retry(res, req_err) then
      break
    end

    if should_cooldown_key(res and res.status or nil, res, req_err) then
      keypool.mark_key_cooldown(provider, key.id, runtime.key_cooldown_sec, {
        source = 'non_stream_retry',
        status = res and res.status or nil,
      })
    end

    local next_provider, next_model, next_key = pick_retry_target(
      cfg,
      std_model,
      endpoint_key,
      provider,
      provider_model,
      attempted_keys_by_provider,
      exhausted_providers
    )
    if not next_provider then
      break
    end

    provider = next_provider
    provider_model = next_model
    key = next_key
  end

  ngx.ctx.latency_ms = math.floor((ngx.now() - start_time) * 1000)
  ngx.ctx.provider = final_provider.name
  ngx.ctx.provider_model = final_model
  ngx.ctx.key_id = final_key.id

  if not res then
    local error_details = {
      provider = final_provider.name,
      url = join_url(final_provider.base_url, final_endpoint or endpoint),
      key_id = final_key.id,
      error = req_err or 'unknown error',
      ssl_verify = final_provider.ssl_verify,
      timeout_ms = final_provider.timeout_ms,
    }
    ngx.log(ngx.ERR, '[', format_timestamp(), '] [openai_compat] upstream request failed: ', cjson.encode(error_details))
    ngx.ctx.error_type = 'upstream_error'
    ngx.ctx.error_details = error_details
    return errors.send(502, 'upstream request failed', 'upstream_error')
  end

  ngx.ctx.upstream_status = res.status
  ngx.ctx.error_type = classify_error(res.status, req_err)

  copy_response_headers(res.headers)
  observe.maybe_expose_selection(final_provider, final_key)

  ngx.status = res.status
  ngx.say(inject_channel_to_json_response(res.body or '', final_provider.name))
  return ngx.exit(res.status)
end

return _M
