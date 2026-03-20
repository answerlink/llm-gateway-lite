local runtime = require('config.runtime')
local cjson = require('cjson.safe')

local _M = {}

local function unauthorized(message)
  ngx.status = 401
  ngx.header['Content-Type'] = 'application/json'
  ngx.say(cjson.encode({
    error = {
      message = message or 'admin auth required',
      type = 'authentication_error',
    },
  }))
  return ngx.exit(401)
end

local function redirect_to_login()
  local next_url = ngx.var.request_uri or '/admin/dashboard'
  local target = '/admin/login?next=' .. ngx.escape_uri(next_url)
  return ngx.redirect(target, 302)
end

local function extract_token()
  local headers = ngx.req.get_headers()
  local token = headers['X-Admin-Token'] or headers['x-admin-token']
  if token and token ~= '' then
    return token
  end

  local auth = headers['Authorization'] or headers['authorization']
  if auth and auth ~= '' then
    local bearer = auth:match('^Bearer%s+(.+)$')
    if bearer and bearer ~= '' then
      return bearer
    end
  end

  local args = ngx.req.get_uri_args()
  if args and args.admin_token and args.admin_token ~= '' then
    return args.admin_token
  end

  return nil
end

function _M.guard()
  local expected = runtime.getenv('GATEWAY_ADMIN_TOKEN')
  if not expected or expected == '' then
    return true
  end

  local got = extract_token()
  if got and got == expected then
    return true
  end

  -- For browser dashboard pages, provide a login entry instead of raw 401 JSON.
  local uri = ngx.var.uri or ''
  if ngx.req.get_method() == 'GET' and uri:find('^/admin/dashboard') then
    return redirect_to_login()
  end

  return unauthorized('invalid admin token')
end

return _M
