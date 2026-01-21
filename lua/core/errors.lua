local cjson = require('cjson.safe')

local _M = {}

function _M.send(status, message, err_type, code)
  ngx.status = status
  ngx.header['Content-Type'] = 'application/json'
  local payload = {
    error = {
      message = message or 'request failed',
      type = err_type or 'invalid_request_error',
      code = code,
    },
  }
  ngx.say(cjson.encode(payload))
  return ngx.exit(status)
end

function _M.bad_request(message)
  return _M.send(400, message, 'invalid_request_error')
end

function _M.not_found(message)
  return _M.send(404, message or 'not found', 'not_found')
end

function _M.unavailable(message)
  return _M.send(503, message or 'service unavailable', 'service_unavailable')
end

return _M
