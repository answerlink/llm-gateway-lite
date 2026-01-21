local _M = {}

local state = ngx.shared and ngx.shared.gateway_state or nil
local rr = ngx.shared and ngx.shared.gateway_rr or nil

local function cooldown_key(provider, key_id)
  return 'cooldown:' .. provider.name .. ':' .. key_id
end

function _M.is_key_available(provider, key)
  if not state then
    return true
  end
  local value = state:get(cooldown_key(provider, key.id))
  return value == nil
end

function _M.mark_key_cooldown(provider, key_id, ttl)
  if not state then
    return
  end
  state:set(cooldown_key(provider, key_id), true, ttl)
end

function _M.pick_key(provider, opts)
  if not provider or not provider.keys or #provider.keys == 0 then
    return nil
  end

  local exclude = opts and opts.exclude_key_id or nil
  local count = #provider.keys
  local start = 1

  if rr then
    local idx = rr:incr('rr:' .. provider.name, 1, 0)
    start = (idx % count) + 1
  end

  for i = 0, count - 1 do
    local key = provider.keys[((start + i - 1) % count) + 1]
    if (not exclude or key.id ~= exclude) and _M.is_key_available(provider, key) then
      return key
    end
  end

  return nil
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

return _M
