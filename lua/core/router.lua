local keypool = require('core.keypool')

local _M = {}

local function weighted_choice(candidates, total_weight)
  if #candidates == 1 then
    return candidates[1]
  end

  local pick = math.random() * total_weight
  local acc = 0
  for _, item in ipairs(candidates) do
    acc = acc + item.weight
    if pick <= acc then
      return item
    end
  end
  return candidates[#candidates]
end

local function allow_provider(model_policy, provider_name)
  if not model_policy or not model_policy.allow_set then
    return true
  end
  return model_policy.allow_set[provider_name] == true
end

function _M.select_provider(config, std_model, opts)
  if not config or not std_model then
    return nil, nil, 'invalid arguments'
  end

  local model = config.models[std_model]
  if not model then
    return nil, nil, 'unsupported_model'
  end

  local exclude = opts and opts.exclude_providers or {}
  local candidates = {}
  local total = 0

  local prefer = opts and opts.prefer_provider
  if prefer and not exclude[prefer] and allow_provider(model.policy, prefer) then
    local provider = config.providers[prefer]
    local provider_model = model.provider_map[prefer]
    if provider and provider_model and keypool.has_available_key(provider) then
      return provider, provider_model
    end
  end

  if model.policy and model.policy.default_provider then
    local default_name = model.policy.default_provider
    if not exclude[default_name] and allow_provider(model.policy, default_name) then
      local provider = config.providers[default_name]
      local provider_model = model.provider_map[default_name]
      if provider and provider_model and keypool.has_available_key(provider) then
        return provider, provider_model
      end
    end
  end

  for provider_name, provider_model in pairs(model.provider_map or {}) do
    if not exclude[provider_name] and allow_provider(model.policy, provider_name) then
      local provider = config.providers[provider_name]
      if provider and keypool.has_available_key(provider) then
        local weight = tonumber(provider.weight) or 1
        table.insert(candidates, {
          name = provider_name,
          weight = weight,
          model = provider_model,
        })
        total = total + weight
      end
    end
  end

  if #candidates == 0 then
    return nil, nil, 'no_provider_available'
  end

  local selected = weighted_choice(candidates, total)
  return config.providers[selected.name], selected.model
end

return _M
