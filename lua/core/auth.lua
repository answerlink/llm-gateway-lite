-- 客户端鉴权模块
local runtime = require('config.runtime')

local _M = {}

-- 从请求中提取 API Key
local function extract_api_key()
  -- 1. 尝试从 Authorization header 获取
  local auth_header = ngx.req.get_headers()['Authorization']
  if auth_header then
    -- 支持 "Bearer sk-xxx" 或 "sk-xxx"
    local key = auth_header:match('^Bearer%s+(.+)$')
    if key then
      return key
    end
    -- 直接是 key
    if auth_header:match('^sk%-') then
      return auth_header
    end
  end
  
  -- 2. 尝试从 x-api-key header 获取
  local api_key_header = ngx.req.get_headers()['x-api-key']
  if api_key_header then
    return api_key_header
  end
  
  -- 3. 尝试从 query 参数获取（不推荐，但兼容）
  local args = ngx.req.get_uri_args()
  if args['api_key'] then
    return args['api_key']
  end
  
  return nil
end

-- 验证 API Key
function _M.validate()
  -- 检查环境变量是否启用鉴权（从文件读取）
  local file = io.open('/tmp/gateway/auth_enabled', 'r')
  if file then
    local auth_enabled = file:read('*line')
    file:close()
    
    if auth_enabled and (auth_enabled == 'false' or auth_enabled == 'False' or auth_enabled == '0') then
      ngx.log(ngx.INFO, '[auth] Authentication disabled by GATEWAY_AUTH_ENABLED configuration')
      return true
    end
  end
  
  local cfg = runtime.get_config()
  if not cfg then
    return false, 'config not loaded'
  end
  
  -- 如果没有配置 gateway_keys，则不进行鉴权（向后兼容）
  if not cfg.gateway_keys or #cfg.gateway_keys == 0 then
    ngx.log(ngx.WARN, '[auth] No gateway API keys configured, authentication disabled')
    return true
  end
  
  -- 提取客户端提供的 API Key
  local client_key = extract_api_key()
  if not client_key then
    return false, 'missing API key'
  end
  
  -- 验证 API Key
  for _, key_config in ipairs(cfg.gateway_keys) do
    if key_config.key == client_key then
      -- 验证通过，记录租户信息
      ngx.ctx.tenant_id = key_config.tenant_id or key_config.key_id
      ngx.ctx.key_id = key_config.key_id
      
      -- 可选：检查是否启用
      if key_config.enabled == false then
        return false, 'API key disabled'
      end
      
      -- 可选：检查允许的模型
      if key_config.allowed_models then
        ngx.ctx.allowed_models = key_config.allowed_models
      end
      
      ngx.log(ngx.INFO, '[auth] API key validated: tenant_id=', ngx.ctx.tenant_id)
      return true
    end
  end
  
  return false, 'invalid API key'
end

return _M
