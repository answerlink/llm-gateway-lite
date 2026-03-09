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

local function apply_headers(headers)
  for name, value in pairs(headers) do
    ngx.req.set_header(name, value)
  end
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

local function should_retry(status, err)
  if err then
    return true
  end
  if not status then
    return true
  end
  if status == 401 or status == 403 or status == 429 then
    return true
  end
  if status == 400 then
    return true
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

  local std_model = normalize.to_standard(cfg, input_model)
  if not std_model then
    ngx.ctx.error_type = 'invalid_model'
    return errors.bad_request('unsupported model: ' .. tostring(input_model))
  end

  ngx.ctx.input_model = input_model
  ngx.ctx.std_model = std_model

  local select_opts = { prefer_provider = 'lark-code-plan' }

  local provider, provider_model, select_err = router.select_provider(cfg, std_model, select_opts)
  if not provider then
    ngx.ctx.error_type = 'no_provider'
    if select_err == 'no_provider_available' then
      return errors.unavailable('no provider available')
    end
    return errors.unavailable('provider selection failed')
  end

  -- 对 minimax-m2.5 增加选路可观测性：默认应优先 lark-code-plan，若未命中则打印 key 可用性。
  if std_model == 'minimax-m2.5' and provider.name ~= 'lark-code-plan' then
    local prefer = cfg.providers and cfg.providers['lark-code-plan'] or nil
    local prefer_info = keypool.inspect_provider(prefer)
    local selected_info = keypool.inspect_provider(provider)
    ngx.log(
      ngx.WARN,
      '[', format_timestamp(), '] [routing_debug] ',
      safe_json_encode({
        event = 'prefer_provider_skipped',
        model = std_model,
        prefer_provider = 'lark-code-plan',
        selected_provider = provider.name,
        prefer_provider_keys = prefer_info,
        selected_provider_keys = selected_info,
      })
    )
  end

  local key = keypool.pick_key(provider)
  if not key then
    ngx.ctx.error_type = 'no_key'
    return errors.unavailable('no key available for provider')
  end

  local endpoint = provider.endpoints and provider.endpoints[endpoint_key] or nil
  if not endpoint then
    ngx.ctx.error_type = 'config_error'
    return errors.unavailable('provider endpoint not configured')
  end

  body.model = provider_model
  local body_json, encode_err = rewrite.encode_body(body)
  if not body_json then
    ngx.ctx.error_type = 'invalid_request'
    return errors.bad_request('failed to encode body: ' .. tostring(encode_err))
  end

  local is_stream = body.stream == true
  ngx.ctx.stream = is_stream

  if is_stream then
    ngx.ctx.provider = provider.name
    ngx.ctx.provider_model = provider_model
    ngx.ctx.key_id = key.id

    local headers = build_headers(provider, key, ngx.ctx.request_id)
    apply_headers(headers)

    ngx.req.set_body_data(body_json)
    ngx.req.set_header('Content-Length', #body_json)

    observe.maybe_expose_selection(provider, key)
    local upstream_url = join_url(provider.base_url, endpoint)
    log_upstream_request(provider, upstream_url, headers, body_json)
    ngx.var.upstream_url = upstream_url
    ngx.var.upstream_host = provider.host
    ngx.var.upstream_host_header = provider.host_header
    ngx.var.is_stream = "true"  -- 使用 Nginx 变量传递流式标志
    
    -- 通过 Nginx 变量传递关键信息（ngx.exec 后 ngx.ctx 会被重置）
    ngx.var.stream_provider = provider.name
    ngx.var.stream_provider_model = provider_model
    ngx.var.stream_input_model = std_model
    ngx.var.stream_request_id = ngx.ctx.request_id or ""

    return ngx.exec('@proxy_stream')
  end

  local start_time = ngx.now()
  local url = join_url(provider.base_url, endpoint)
  local request_headers = build_headers(provider, key, ngx.ctx.request_id)
  
  ngx.log(ngx.INFO, '[', format_timestamp(), '] [openai_compat] making request: provider=', provider.name, ', url=', url, ', model=', provider_model, ', key_id=', key.id, ', ssl_verify=', provider.ssl_verify)
  log_upstream_request(provider, url, request_headers, body_json)
  
  local res, req_err = do_request(provider, key, endpoint, body_json, ngx.ctx.request_id)

  -- 记录失败请求的详细信息
  if not res and req_err then
    ngx.log(ngx.ERR, '[', format_timestamp(), '] [openai_compat] request failed: provider=', provider.name, ', url=', url, ', error=', req_err, ', key_id=', key.id)
    log_failed_request(provider, url, request_headers, body_json, nil, req_err)
  elseif res and res.status ~= 200 then
    -- 非 200 响应也记录详细信息
    ngx.log(ngx.WARN, '[', format_timestamp(), '] [openai_compat] request response: provider=', provider.name, ', status=', res.status, ', body_size=', #(res.body or ''))
    log_failed_request(provider, url, request_headers, body_json, res, nil)
  elseif res then
    ngx.log(ngx.INFO, '[', format_timestamp(), '] [openai_compat] request response: provider=', provider.name, ', status=', res.status, ', body_size=', #(res.body or ''))
  end

  local final_provider = provider
  local final_key = key
  local final_model = provider_model

  if should_retry(res and res.status or nil, req_err) then
    local retry_provider = nil
    local retry_key = nil
    local retry_model = provider_model

    if res and (res.status == 401 or res.status == 403 or res.status == 429) then
      keypool.mark_key_cooldown(provider, key.id, runtime.key_cooldown_sec)
      retry_provider = provider
      retry_key = keypool.pick_key(provider, { exclude_key_id = key.id })
      retry_model = provider_model
    end

    if not retry_key then
      local exclude = { [provider.name] = true }
      local alt_provider, alt_model = router.select_provider(cfg, std_model, { exclude_providers = exclude })
      if alt_provider then
        local alt_key = keypool.pick_key(alt_provider)
        if alt_key then
          retry_provider = alt_provider
          retry_key = alt_key
          retry_model = alt_model
        end
      end
    end

    if retry_provider and retry_key then
      final_provider = retry_provider
      final_key = retry_key
      final_model = retry_model

      body.model = final_model
      local retry_body, retry_err = rewrite.encode_body(body)
      if not retry_body then
        ngx.ctx.error_type = 'invalid_request'
        return errors.bad_request('failed to encode retry body: ' .. tostring(retry_err))
      end
      body_json = retry_body

      local retry_endpoint = final_provider.endpoints and final_provider.endpoints[endpoint_key] or nil
      if not retry_endpoint then
        ngx.ctx.error_type = 'config_error'
        return errors.unavailable('retry provider endpoint not configured')
      end

      local retry_url = join_url(final_provider.base_url, retry_endpoint)
      local retry_headers = build_headers(final_provider, final_key, ngx.ctx.request_id)
      
      ngx.log(ngx.INFO, '[', format_timestamp(), '] [openai_compat] retrying with provider=', final_provider.name, ', url=', retry_url, ', key_id=', final_key.id)
      log_upstream_request(final_provider, retry_url, retry_headers, body_json)
      
      res, req_err = do_request(final_provider, final_key, retry_endpoint, body_json, ngx.ctx.request_id)
      
      -- 记录重试失败
      if not res and req_err then
        log_failed_request(final_provider, retry_url, retry_headers, body_json, nil, req_err)
      elseif res and res.status ~= 200 then
        log_failed_request(final_provider, retry_url, retry_headers, body_json, res, nil)
      end
    end
  end

  ngx.ctx.latency_ms = math.floor((ngx.now() - start_time) * 1000)
  ngx.ctx.provider = final_provider.name
  ngx.ctx.provider_model = final_model
  ngx.ctx.key_id = final_key.id

  if not res then
    local error_details = {
      provider = final_provider.name,
      url = join_url(final_provider.base_url, endpoint),
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
