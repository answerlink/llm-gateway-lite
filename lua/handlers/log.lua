local observe = require('core.observe')
local cjson = require('cjson.safe')
local runtime = require('config.runtime')
local keypool = require('core.keypool')

local function format_timestamp()
  local now = ngx.now()
  local sec = math.floor(now)
  local msec = math.floor((now - sec) * 1000)
  return os.date('%Y-%m-%d %H:%M:%S', sec) .. string.format('.%03d', msec)
end

-- 记录流式请求的错误（简化版本，因为 ngx.exec 后 ngx.ctx 被重置）
local function log_stream_error()
  local ctx = ngx.ctx or {}
  -- 仅保留旧版 ngx.exec('@proxy_stream') 路径的日志兜底。
  -- 新版流式首包前重试由 openai_compat.lua 内部处理并记录。
  local is_stream = ngx.var.is_stream == "true"
  
  -- 只记录流式请求的非 200 响应
  if not is_stream then
    return
  end
  
  local upstream_status = ctx.upstream_status or ngx.var.upstream_status or ngx.status
  local status_num = tonumber(upstream_status)
  
  -- 只记录非 200 响应
  if not status_num or status_num == 200 then
    return
  end
  
  -- 从 Nginx 变量恢复关键信息（ngx.exec 后 ngx.ctx 被重置）
  local request_id = ctx.request_id
  local provider = ctx.provider
  local provider_model = ctx.provider_model
  local input_model = ctx.input_model
  local key_id = ctx.key_id
  
  if not request_id then
    request_id = ngx.var.stream_request_id ~= "" and ngx.var.stream_request_id or nil
    provider = ngx.var.stream_provider ~= "" and ngx.var.stream_provider or nil
    provider_model = ngx.var.stream_provider_model ~= "" and ngx.var.stream_provider_model or nil
    input_model = ngx.var.stream_input_model ~= "" and ngx.var.stream_input_model or nil
    key_id = ngx.var.stream_key_id ~= "" and ngx.var.stream_key_id or nil
  end

  if key_id and provider and (status_num == 401 or status_num == 402 or status_num == 403 or status_num == 429) then
    local cfg = runtime.get_config()
    local provider_cfg = cfg and cfg.providers and cfg.providers[provider] or nil
    if provider_cfg then
      keypool.mark_key_cooldown(provider_cfg, key_id, runtime.key_cooldown_sec, {
        source = 'stream_log',
        status = status_num,
      })
    end
  end
  
  -- 流式请求由于使用 ngx.exec('@proxy_stream')，无法在 log 阶段获取原始请求体
  -- 只记录关键的元信息
  local log_entry = {
    timestamp = format_timestamp(),
    level = 'ERROR',
    event = 'stream_request_failed',
    request_id = request_id,
    provider = provider,
    provider_model = provider_model,
    key_id = key_id,
    input_model = input_model,
    response = {
      status = status_num,
    },
    note = 'Stream request - request/response body not available due to proxy_pass',
  }
  
  ngx.log(ngx.ERR, '[', format_timestamp(), '] ', cjson.encode(log_entry))
end

-- 先记录流式错误（如果有）
log_stream_error()

-- 然后记录常规的 observe 日志
observe.log_request()
