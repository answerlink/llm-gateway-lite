local _M = {}

_M.config = nil
_M.config_hash = nil
_M.env_cache = {}
_M.reload_interval = tonumber(os.getenv('GATEWAY_RELOAD_INTERVAL_SEC') or '5') or 5
_M.key_cooldown_sec = tonumber(os.getenv('GATEWAY_KEY_COOLDOWN_SEC') or '600') or 600
_M.expose_selection_headers = os.getenv('GATEWAY_EXPOSE_SELECTION') == '1'

-- 从文件读取鉴权开关（解决 OpenResty 环境变量访问问题）
local function read_auth_enabled()
  local file = io.open('/tmp/gateway/auth_enabled', 'r')
  if file then
    local value = file:read('*line')
    file:close()
    return value
  end
  return 'true'  -- 默认启用鉴权
end

_M.auth_enabled = read_auth_enabled()

function _M.getenv(name)
  local cached = _M.env_cache[name]
  if cached ~= nil then
    if cached == false then
      return nil
    end
    return cached
  end

  local val = os.getenv(name)
  if val == nil then
    _M.env_cache[name] = false
  else
    _M.env_cache[name] = val
  end
  return val
end

function _M.set_config(cfg, hash)
  _M.config = cfg
  _M.config_hash = hash
end

function _M.get_config()
  return _M.config
end

function _M.get_hash()
  return _M.config_hash
end

return _M
