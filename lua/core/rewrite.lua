local cjson = require('cjson.safe')

local _M = {}

function _M.encode_body(body)
  return cjson.encode(body)
end

function _M.update_model(body, provider_model)
  body.model = provider_model
  return _M.encode_body(body)
end

return _M
