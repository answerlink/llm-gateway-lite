local cjson = require('cjson.safe')
local runtime = require('config.runtime')
local stats = require('core.stats')

local _M = {}

local function generate_id()
  local ok_rand, rand = pcall(require, 'resty.random')
  local ok_str, str = pcall(require, 'resty.string')
  if ok_rand and ok_str then
    local bytes = rand.bytes(16, true)
    if bytes then
      return str.to_hex(bytes)
    end
  end
  local time_ms = math.floor(ngx.now() * 1000)
  local pid = ngx.worker and ngx.worker.pid() or 0
  local rand_part = math.random(0, 0xfffff)
  return string.format('%x-%x-%x', time_ms, pid, rand_part)
end

function _M.start_request()
  ngx.ctx.start_time = ngx.now()
  local headers = ngx.req.get_headers()
  local request_id = headers['X-Request-Id'] or headers['X-Request-ID']
  if not request_id or request_id == '' then
    request_id = generate_id()
  end
  ngx.ctx.request_id = request_id
  ngx.header['X-Request-Id'] = request_id
end

function _M.maybe_expose_selection(provider, key)
  if not runtime.expose_selection_headers then
    return
  end
  if provider then
    ngx.header['X-Selected-Provider'] = provider.name
  end
  if key then
    ngx.header['X-Selected-Key-Id'] = key.id
  end
end

local function parse_status(value)
  if type(value) == 'number' then
    return value
  end
  if type(value) == 'string' then
    local first = value:match('^(%d+)')
    return tonumber(first)
  end
  return nil
end

local function classify_status(status)
  if not status then
    return nil
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

function _M.log_request()
  local ctx = ngx.ctx or {}
  local upstream_status = ctx.upstream_status or ngx.var.upstream_status or ngx.status
  local status_num = parse_status(upstream_status)
  local start_time = ctx.start_time or ngx.req.start_time()
  local latency_ms = ctx.latency_ms or math.floor((ngx.now() - start_time) * 1000)
  
  -- 从 Nginx 变量读取流式标志（用于 ngx.exec 后的情况）
  local is_stream = ctx.stream == true or ngx.var.is_stream == "true"
  
  -- 对于流式请求，从 Nginx 变量恢复关键信息（ngx.exec 后 ngx.ctx 被重置）
  local request_id = ctx.request_id
  local provider = ctx.provider
  local provider_model = ctx.provider_model
  local input_model = ctx.input_model
  local key_id = ctx.key_id
  
  if is_stream and not request_id then
    request_id = ngx.var.stream_request_id ~= "" and ngx.var.stream_request_id or nil
    provider = ngx.var.stream_provider ~= "" and ngx.var.stream_provider or nil
    provider_model = ngx.var.stream_provider_model ~= "" and ngx.var.stream_provider_model or nil
    input_model = ngx.var.stream_input_model ~= "" and ngx.var.stream_input_model or nil
    key_id = ngx.var.stream_key_id ~= "" and ngx.var.stream_key_id or nil
  end

  local entry = {
    request_id = request_id,
    tenant_id = ctx.tenant_id,
    input_model = input_model,
    std_model = ctx.std_model or input_model,
    provider = provider,
    key_id = key_id,
    provider_model = provider_model,
    upstream_status = status_num or upstream_status,
    latency_ms = latency_ms,
    stream = is_stream,
    error_type = ctx.error_type or classify_status(status_num),
  }

  if not ctx.skip_stats then
    stats.record(entry)
  end

  local line = cjson.encode(entry)
  if not line then
    return
  end

  local level = ngx.INFO
  if status_num and status_num >= 500 then
    level = ngx.ERR
  end
  ngx.log(level, line)
end

return _M
