local _M = {}

local function add_error(errors, message)
  table.insert(errors, message)
end

function _M.validate(cfg)
  local errors = {}

  if cfg.version ~= nil and cfg.version ~= 1 then
    add_error(errors, 'unsupported version: ' .. tostring(cfg.version))
  end

  if type(cfg.providers) ~= 'table' then
    add_error(errors, 'providers must be a table')
  end

  if type(cfg.models) ~= 'table' then
    add_error(errors, 'models must be a table')
  end

  if #errors > 0 then
    return false, errors
  end

  for name, provider in pairs(cfg.providers or {}) do
    if type(provider.base_url) ~= 'string' or provider.base_url == '' then
      add_error(errors, 'provider ' .. name .. ' missing base_url')
    end
    if provider.endpoints ~= nil and type(provider.endpoints) ~= 'table' then
      add_error(errors, 'provider ' .. name .. ' endpoints must be a table')
    end
    if provider.keys ~= nil and type(provider.keys) ~= 'table' then
      add_error(errors, 'provider ' .. name .. ' keys must be a list')
    end
    if provider.request_defaults ~= nil and type(provider.request_defaults) ~= 'table' then
      add_error(errors, 'provider ' .. name .. ' request_defaults must be a table')
    end
  end

  for name, model in pairs(cfg.models or {}) do
    if type(model.provider_map) ~= 'table' then
      add_error(errors, 'model ' .. name .. ' provider_map must be a table')
    end
  end

  if #errors > 0 then
    return false, errors
  end

  return true
end

return _M
