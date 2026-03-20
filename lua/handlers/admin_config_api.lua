local cjson = require('cjson.safe')
local admin_auth = require('core.admin_auth')
local cfg_mgr = require('core.config_manager')

ngx.ctx.skip_stats = true

if not admin_auth.guard() then
  return
end

local function write_json(status, payload)
  ngx.status = status
  ngx.header['Content-Type'] = 'application/json'
  ngx.say(cjson.encode(payload))
end

local function forbidden_if_readonly()
  local editable = (os.getenv('GATEWAY_CONFIG_EDITABLE') or 'true') ~= 'false'
  if editable then
    return false
  end
  write_json(403, {
    error = {
      message = 'config editing is disabled',
      type = 'forbidden',
    },
  })
  return true
end

if ngx.req.get_method() == 'GET' then
  local args = ngx.req.get_uri_args()
  local action = args.action or 'index'

  if action == 'index' then
    local payload, err = cfg_mgr.index_payload()
    if not payload then
      write_json(500, { error = { message = err, type = 'internal_error' } })
      return
    end
    write_json(200, payload)
    return
  end

  if action == 'current' then
    local payload, err = cfg_mgr.current(args.file or '')
    if not payload then
      write_json(400, { error = { message = err, type = 'invalid_request' } })
      return
    end
    write_json(200, payload)
    return
  end

  if action == 'history' then
    local payload, err = cfg_mgr.history(args.file or '', tonumber(args.limit) or 50)
    if not payload then
      write_json(400, { error = { message = err, type = 'invalid_request' } })
      return
    end
    write_json(200, payload)
    return
  end

  if action == 'version' then
    local payload, err = cfg_mgr.version(args.file or '', args.version or '')
    if not payload then
      write_json(400, { error = { message = err, type = 'invalid_request' } })
      return
    end
    write_json(200, payload)
    return
  end

  write_json(400, { error = { message = 'unsupported action', type = 'invalid_request' } })
  return
end

if ngx.req.get_method() == 'POST' then
  if forbidden_if_readonly() then
    return
  end
  ngx.req.read_body()
  local body = ngx.req.get_body_data()
  if not body then
    write_json(400, { error = { message = 'empty body', type = 'invalid_request' } })
    return
  end
  local req = cjson.decode(body)
  if not req then
    write_json(400, { error = { message = 'invalid json body', type = 'invalid_request' } })
    return
  end
  local action = req.action or 'save'
  if action ~= 'save' then
    write_json(400, { error = { message = 'unsupported action', type = 'invalid_request' } })
    return
  end

  local payload, err = cfg_mgr.save(req.file or '', req.content, req.operator or 'admin')
  if not payload then
    write_json(400, { error = { message = err, type = 'validation_error' } })
    return
  end
  write_json(200, payload)
  return
end

write_json(405, { error = { message = 'method not allowed', type = 'method_not_allowed' } })
