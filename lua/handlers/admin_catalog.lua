local cjson = require('cjson.safe')
local runtime = require('config.runtime')
local admin_auth = require('core.admin_auth')

ngx.ctx.skip_stats = true

if not admin_auth.guard() then
  return
end

local function sorted_keys(tbl)
  local keys = {}
  for k, _ in pairs(tbl or {}) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end

local function to_bool(v)
  return v == true
end

local function count_tenants(keys)
  local seen = {}
  for _, key in ipairs(keys or {}) do
    local tenant = key.tenant_id
    if type(tenant) == 'string' and tenant ~= '' then
      seen[tenant] = true
    end
  end
  local total = 0
  for _, _ in pairs(seen) do
    total = total + 1
  end
  return total
end

local cfg = runtime.get_config()
if not cfg then
  ngx.status = 503
  ngx.header['Content-Type'] = 'application/json'
  ngx.say(cjson.encode({
    error = {
      message = 'config not loaded',
      type = 'service_unavailable',
    },
  }))
  return
end

local providers = {}
for _, provider_name in ipairs(sorted_keys(cfg.providers or {})) do
  local provider = cfg.providers[provider_name] or {}
  local endpoints = {}
  for _, endpoint_name in ipairs(sorted_keys(provider.endpoints or {})) do
    table.insert(endpoints, endpoint_name)
  end

  table.insert(providers, {
    name = provider_name,
    type = provider.type,
    base_url = provider.base_url,
    host = provider.host,
    weight = provider.weight,
    timeout_ms = provider.timeout_ms,
    ssl_verify = provider.ssl_verify,
    key_count = #(provider.keys or {}),
    endpoints = endpoints,
  })
end

local models = {}
for _, model_name in ipairs(cfg.model_list or {}) do
  local model = cfg.models[model_name] or {}
  local allow_providers = model.policy and model.policy.allow_providers or {}
  local provider_map = {}
  for _, provider_name in ipairs(sorted_keys(model.provider_map or {})) do
    provider_map[provider_name] = model.provider_map[provider_name]
  end

  table.insert(models, {
    id = model_name,
    aliases = model.aliases or {},
    default_provider = model.policy and model.policy.default_provider or nil,
    allow_providers = allow_providers,
    provider_map = provider_map,
    provider_count = #sorted_keys(model.provider_map or {}),
  })
end

local gateway_keys = {}
local enabled_keys = 0
for _, key_cfg in ipairs(cfg.gateway_keys or {}) do
  local enabled = key_cfg.enabled ~= false
  if enabled then
    enabled_keys = enabled_keys + 1
  end
  table.insert(gateway_keys, {
    key_id = key_cfg.key_id,
    tenant_id = key_cfg.tenant_id,
    enabled = enabled,
    description = key_cfg.description,
    allowed_models_count = type(key_cfg.allowed_models) == 'table' and #key_cfg.allowed_models or 0,
  })
end

local payload = {
  generated_at = math.floor(ngx.now()),
  runtime = {
    config_hash = runtime.get_hash(),
    reload_interval_sec = runtime.reload_interval,
    auth_enabled = runtime.auth_enabled == 'true',
    expose_selection_headers = to_bool(runtime.expose_selection_headers),
    admin_token_enabled = (runtime.getenv('GATEWAY_ADMIN_TOKEN') or '') ~= '',
  },
  summary = {
    models = #models,
    providers = #providers,
    gateway_keys_total = #gateway_keys,
    gateway_keys_enabled = enabled_keys,
    tenants = count_tenants(cfg.gateway_keys or {}),
  },
  models = models,
  providers = providers,
  gateway_keys = gateway_keys,
}

ngx.header['Content-Type'] = 'application/json'
ngx.say(cjson.encode(payload))
