local cjson = require('cjson.safe')
local runtime = require('config.runtime')
local errors = require('core.errors')
local observe = require('core.observe')
local auth = require('core.auth')

local function format_timestamp()
  local now = ngx.now()
  local sec = math.floor(now)
  local msec = math.floor((now - sec) * 1000)
  return os.date('%Y-%m-%d %H:%M:%S', sec) .. string.format('.%03d', msec)
end

observe.start_request()

ngx.log(ngx.INFO, '[', format_timestamp(), '] [models] received request for /v1/models')

-- 鉴权检查
local auth_ok, auth_err = auth.validate()
if not auth_ok then
  ngx.ctx.error_type = 'auth_failed'
  ngx.log(ngx.WARN, '[models] authentication failed: ', auth_err or 'unknown')
  return errors.send(401, auth_err or 'authentication failed', 'authentication_error')
end

local cfg = runtime.get_config()
if not cfg then
  ngx.ctx.error_type = 'config_error'
  ngx.log(ngx.ERR, '[', format_timestamp(), '] [models] config not loaded')
  return errors.unavailable('config not loaded')
end

local data = {}
for _, model_id in ipairs(cfg.model_list or {}) do
  table.insert(data, { id = model_id })
end

ngx.log(ngx.INFO, '[', format_timestamp(), '] [models] returning ', #data, ' models')
ngx.header['Content-Type'] = 'application/json'
ngx.say(cjson.encode({ data = data }))
