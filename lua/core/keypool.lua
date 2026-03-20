local _M = {}
local stats = require('core.stats')

local state = ngx.shared and ngx.shared.gateway_state or nil
local rr = ngx.shared and ngx.shared.gateway_rr or nil

local function cooldown_key(provider, key_id)
  return 'cooldown:' .. provider.name .. ':' .. key_id
end

function _M.is_key_available(provider, key)
  if not key then
    return false
  end
  if not state then
    return true
  end
  local value = state:get(cooldown_key(provider, key.id))
  return value == nil
end

function _M.mark_key_cooldown(provider, key_id, ttl, opts)
  if not state then
    return
  end
  state:set(cooldown_key(provider, key_id), true, ttl)
  if provider and provider.name and key_id then
    stats.record_key_cooldown(provider.name, key_id, ttl, opts)
  end
end

function _M.pick_key(provider, opts)
  if not provider or not provider.keys or #provider.keys == 0 then
    return nil
  end

  local exclude = opts and opts.exclude_key_id or nil
  local exclude_set = opts and opts.exclude_key_ids or nil
  local count = #provider.keys
  local start = 1

  if rr then
    local idx = rr:incr('rr:' .. provider.name, 1, 0)
    start = (idx % count) + 1
  end

  for i = 0, count - 1 do
    local key = provider.keys[((start + i - 1) % count) + 1]
    if (not exclude or key.id ~= exclude)
      and (not exclude_set or exclude_set[key.id] ~= true)
      and _M.is_key_available(provider, key) then
      return key
    end
  end

  return nil
end

function _M.pick_from_provider_chain(chain_items, opts)
  if type(chain_items) ~= 'table' or #chain_items == 0 then
    return nil, nil, nil
  end

  local exclude_by_provider = opts and opts.exclude_key_ids_by_provider or {}
  local chain_id = (opts and opts.chain_id) or 'default'
  local slots = {}

  for _, item in ipairs(chain_items) do
    local provider = item.provider
    if provider and type(provider.keys) == 'table' and #provider.keys > 0 then
      local exclude_set = exclude_by_provider[provider.name] or {}
      for _, key in ipairs(provider.keys) do
        if (not exclude_set[key.id]) and _M.is_key_available(provider, key) then
          table.insert(slots, {
            provider = provider,
            key = key,
            model = item.model,
          })
        end
      end
    end
  end

  local count = #slots
  if count == 0 then
    return nil, nil, nil
  end

  local start = 1
  if rr then
    local idx = rr:incr('rr:chain:' .. tostring(chain_id), 1, 0)
    start = (idx % count) + 1
  end

  local selected = slots[start]
  return selected.provider, selected.model, selected.key
end

function _M.has_available_key(provider)
  if not provider or not provider.keys or #provider.keys == 0 then
    return false
  end
  for _, key in ipairs(provider.keys) do
    if _M.is_key_available(provider, key) then
      return true
    end
  end
  return false
end

function _M.inspect_provider(provider)
  local info = {
    provider = provider and provider.name or nil,
    total_keys = 0,
    available_keys = 0,
    cooldown_keys = {},
  }

  if not provider or not provider.keys then
    return info
  end

  info.total_keys = #provider.keys

  for _, key in ipairs(provider.keys) do
    if _M.is_key_available(provider, key) then
      info.available_keys = info.available_keys + 1
    else
      local item = { id = key.id }
      if state and state.ttl then
        local ttl = state:ttl(cooldown_key(provider, key.id))
        if ttl and ttl >= 0 then
          item.ttl = ttl
        end
      end
      table.insert(info.cooldown_keys, item)
    end
  end

  return info
end

function _M.inspect_provider_keys(provider)
  local keys = {}
  if not provider or not provider.keys then
    return keys
  end

  for _, key in ipairs(provider.keys) do
    local available = _M.is_key_available(provider, key)
    local item = {
      id = key.id,
      available = available,
      cooldown_ttl = 0,
    }
    if not available and state and state.ttl then
      local ttl = state:ttl(cooldown_key(provider, key.id))
      if ttl and ttl > 0 then
        item.cooldown_ttl = ttl
      end
    end
    table.insert(keys, item)
  end

  return keys
end

return _M
