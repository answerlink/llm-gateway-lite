local _M = {}

function _M.to_standard(config, input_model)
  if not config or not input_model then
    return nil
  end
  local index = config.alias_index or {}
  return index[input_model]
end

return _M
