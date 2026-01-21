local yaml = require('config.yaml')
local schema = require('config.schema')
local runtime = require('config.runtime')

local _M = {}

local function read_file(path)
  local handle, err = io.open(path, 'rb')
  if not handle then
    return nil, err
  end
  local data = handle:read('*a')
  handle:close()
  return data
end

local function shell_escape(path)
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function list_yaml_files(dir)
  local files = {}
  local command = 'ls -1 ' .. shell_escape(dir) .. '/*.yaml ' .. shell_escape(dir) .. '/*.yml 2>/dev/null'
  local pipe = io.popen(command)
  if not pipe then
    return files
  end
  for line in pipe:lines() do
    if line and line ~= '' then
      table.insert(files, line)
    end
  end
  pipe:close()
  table.sort(files)
  return files
end

local function dirname(path)
  return path:match('^(.*)[/\\][^/\\]+$') or '.'
end

local function join_path(base, path)
  if path:match('^/') or path:match('^[A-Za-z]:[\\/]') then
    return path
  end
  if base:sub(-1) == '/' or base:sub(-1) == '\\' then
    return base .. path
  end
  return base .. '/' .. path
end

local function parse_base_url(url)
  local scheme, rest = url:match('^(https?)://(.+)$')
  if not scheme then
    return nil, 'invalid base_url: ' .. tostring(url)
  end
  local host_port = rest:match('^([^/]+)') or rest
  local host, port = host_port:match('^([^:]+):(%d+)$')
  local port_num = tonumber(port) or (scheme == 'https' and 443 or 80)
  local host_only = host or host_port
  local host_header = host_only
  if port and ((scheme == 'https' and port_num ~= 443) or (scheme == 'http' and port_num ~= 80)) then
    host_header = host_only .. ':' .. port
  end
  return {
    scheme = scheme,
    host = host_only,
    port = port_num,
    host_header = host_header,
  }
end

local function merge_config(base, extra)
  if type(extra.providers) == 'table' then
    for name, provider in pairs(extra.providers) do
      base.providers[name] = provider
    end
  end
  if type(extra.models) == 'table' then
    for name, model in pairs(extra.models) do
      base.models[name] = model
    end
  end
  if type(extra.gateway_keys) == 'table' then
    if not base.gateway_keys then
      base.gateway_keys = {}
    end
    for _, key in ipairs(extra.gateway_keys) do
      table.insert(base.gateway_keys, key)
    end
  end
  if extra.version ~= nil then
    base.version = extra.version
  end
end

local function load_documents(paths)
  local merged = { providers = {}, models = {}, gateway_keys = {} }
  local files = {}
  local contents = {}
  local queue = {}
  local seen = {}

  for _, path in ipairs(paths) do
    table.insert(queue, path)
  end

  while #queue > 0 do
    local path = table.remove(queue, 1)
    if not seen[path] then
      seen[path] = true
      local content, err = read_file(path)
      if not content then
        return nil, nil, nil, 'failed to read ' .. path .. ': ' .. (err or 'unknown error')
      end
      local doc, parse_err = yaml.decode(content)
      if not doc then
        return nil, nil, nil, 'failed to parse ' .. path .. ': ' .. (parse_err or 'unknown error')
      end
      table.insert(files, path)
      contents[path] = content
      if type(doc.include) == 'table' then
        local base_dir = dirname(path)
        for _, inc in ipairs(doc.include) do
          if type(inc) == 'string' and inc ~= '' then
            table.insert(queue, join_path(base_dir, inc))
          end
        end
      end
      merge_config(merged, doc)
    end
  end

  return merged, files, contents
end

local function normalize_config(cfg)
  local out = {
    providers = {},
    models = {},
    alias_index = {},
    model_list = {},
    gateway_keys = {},
  }

  for name, provider in pairs(cfg.providers or {}) do
    if type(provider) == 'table' then
      local parsed, perr = parse_base_url(provider.base_url or '')
      if not parsed then
        if ngx and ngx.log then
          ngx.log(ngx.ERR, perr)
        end
      else
        local auth = provider.auth or {}
        local normalized = {
          name = name,
          type = provider.type or 'openai_compat',
          base_url = provider.base_url,
          scheme = parsed.scheme,
          host = parsed.host,
          host_header = parsed.host_header,
          endpoints = provider.endpoints or {},
          auth = {
            mode = auth.mode or 'bearer',
            header = auth.header or 'Authorization',
            prefix = auth.prefix or 'Bearer ',
          },
          headers = provider.headers or {},
          weight = tonumber(provider.weight) or 1,
          timeout_ms = tonumber(provider.timeout_ms) or 60000,
          ssl_verify = provider.ssl_verify,
          keys = {},
        }

        for _, key in ipairs(provider.keys or {}) do
          if type(key) == 'table' then
            local key_value = nil
            local key_id = key.id or 'unknown'
            
            -- 优先使用直接配置的 value
            if type(key.value) == 'string' and key.value ~= '' then
              key_value = key.value
            -- 否则尝试从环境变量读取
            elseif type(key.value_env) == 'string' and key.value_env ~= '' then
              key_value = runtime.getenv(key.value_env)
              if not key_value or key_value == '' then
                if ngx and ngx.log then
                  ngx.log(ngx.WARN, 'missing env for key ', key.value_env, ' in provider ', name)
                end
              end
            end
            
            -- 如果获取到了有效的密钥值，则添加到 keys 列表
            if key_value and key_value ~= '' then
              table.insert(normalized.keys, {
                id = key_id,
                value = key_value,
              })
            end
          end
        end

        out.providers[name] = normalized
      end
    end
  end

  for name, model in pairs(cfg.models or {}) do
    if type(model) == 'table' then
      local aliases = model.aliases or {}
      local policy = model.policy or {}
      local provider_map = model.provider_map or {}
      
      -- 如果未配置 allow_providers，自动从 provider_map 中提取所有 provider
      local allow_providers = policy.allow_providers
      if not allow_providers or type(allow_providers) ~= 'table' or #allow_providers == 0 then
        allow_providers = {}
        for provider_name, _ in pairs(provider_map) do
          table.insert(allow_providers, provider_name)
        end
        table.sort(allow_providers)  -- 排序以保证一致性
      end
      
      local allow_set = {}
      for _, provider_name in ipairs(allow_providers) do
        allow_set[provider_name] = true
      end

      out.models[name] = {
        id = name,
        aliases = aliases,
        provider_map = provider_map,
        policy = {
          allow_providers = allow_providers,
          allow_set = allow_set,
          default_provider = policy.default_provider,
        },
      }
    end
  end

  for name, model in pairs(out.models) do
    out.alias_index[name] = name
    if type(model.aliases) == 'table' then
      for _, alias in ipairs(model.aliases) do
        out.alias_index[alias] = name
      end
    end
  end

  for name in pairs(out.models) do
    table.insert(out.model_list, name)
  end
  table.sort(out.model_list)

  -- 处理网关 API Keys
  if cfg.gateway_keys and type(cfg.gateway_keys) == 'table' then
    for _, key_cfg in ipairs(cfg.gateway_keys) do
      if type(key_cfg) == 'table' and key_cfg.key then
        table.insert(out.gateway_keys, {
          key_id = key_cfg.key_id or 'unknown',
          key = key_cfg.key,
          tenant_id = key_cfg.tenant_id,
          enabled = key_cfg.enabled ~= false,  -- 默认启用
          description = key_cfg.description,
          allowed_models = key_cfg.allowed_models,
        })
      end
    end
  end

  return out
end

local function compute_hash(files, contents)
  local pieces = {}
  for _, path in ipairs(files) do
    table.insert(pieces, path)
    table.insert(pieces, contents[path] or '')
  end
  local joined = table.concat(pieces, '\n')
  if ngx and ngx.md5 then
    return ngx.md5(joined)
  end
  return tostring(#joined)
end

function _M.load()
  local config_file = os.getenv('GATEWAY_CONFIG_FILE')
  local config_dir = os.getenv('GATEWAY_CONFIG_DIR') or '/etc/llm-gateway/conf.d'
  local paths = {}

  if config_file and config_file ~= '' then
    table.insert(paths, config_file)
  else
    paths = list_yaml_files(config_dir)
  end

  if #paths == 0 then
    return nil, nil, 'no config files found'
  end

  local merged, files, contents, err = load_documents(paths)
  if not merged then
    return nil, nil, err
  end

  local ok, errors = schema.validate(merged)
  if not ok then
    return nil, nil, table.concat(errors or {}, '; ')
  end

  local normalized = normalize_config(merged)
  local hash = compute_hash(files, contents)
  normalized._meta = { files = files, hash = hash }

  return normalized, hash
end

return _M
