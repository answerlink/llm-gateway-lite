local cjson = require('cjson.safe')
local loader = require('config.loader')
local runtime = require('config.runtime')

local _M = {}

local ALLOWED_FILES = {
  ['providers.yaml'] = true,
  ['models.yaml'] = true,
}

local function config_dir()
  return os.getenv('GATEWAY_CONFIG_DIR') or '/etc/llm-gateway/conf.d'
end

local function versions_dir()
  return os.getenv('GATEWAY_CONFIG_VERSION_DIR') or '/var/log/llm-gateway/config-versions'
end

local function shell_escape(path)
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function ensure_allowed(file_name)
  if not ALLOWED_FILES[file_name] then
    return nil, 'unsupported file: ' .. tostring(file_name)
  end
  return true
end

local function join(base, leaf)
  if base:sub(-1) == '/' then
    return base .. leaf
  end
  return base .. '/' .. leaf
end

local function now_bj(ts)
  local t = tonumber(ts) or os.time()
  return os.date('!%Y-%m-%d %H:%M:%S', t + 8 * 3600) .. ' CST'
end

local function read_file(path)
  local f, err = io.open(path, 'rb')
  if not f then
    return nil, err
  end
  local data = f:read('*a')
  f:close()
  return data
end

local function write_file_atomic(path, content)
  local tmp = path .. '.tmp.' .. tostring(os.time()) .. '.' .. tostring(math.random(100000, 999999))
  local f, err = io.open(tmp, 'wb')
  if not f then
    return nil, 'open temp file failed: ' .. tostring(err)
  end
  f:write(content or '')
  f:close()

  local ok, rename_err = os.rename(tmp, path)
  if not ok then
    os.remove(tmp)
    return nil, 'replace target failed: ' .. tostring(rename_err)
  end
  return true
end

local function ensure_dir(path)
  local cmd = 'mkdir -p ' .. shell_escape(path)
  os.execute(cmd)
end

local function version_file_name(file_name, content, ts, tag)
  local stamp = os.date('!%Y%m%d-%H%M%S', ts + 8 * 3600)
  local digest = (ngx and ngx.md5 and ngx.md5(content or '') or tostring(#(content or ''))):sub(1, 10)
  local safe_tag = tag or 'snapshot'
  return file_name:gsub('%.yaml$', '') .. '__' .. stamp .. '__' .. safe_tag .. '__' .. digest .. '.yaml'
end

local function save_version_snapshot(file_name, content, ts, tag)
  ensure_dir(versions_dir())
  local name = version_file_name(file_name, content, ts, tag)
  local path = join(versions_dir(), name)
  local ok, err = write_file_atomic(path, content or '')
  if not ok then
    return nil, err
  end
  return name
end

local function list_versions(file_name)
  local prefix = file_name:gsub('%.yaml$', '') .. '__'
  local cmd = 'ls -1 ' .. shell_escape(versions_dir()) .. '/' .. prefix .. '*__saved__*.yaml 2>/dev/null'
  local p = io.popen(cmd)
  local out = {}
  if not p then
    return out
  end
  for line in p:lines() do
    local name = line:match('([^/]+)$') or line
    local stamp = name:match('__([0-9]+%-[0-9]+)__')
    local bj = '-'
    if stamp then
      local y, m, d, hh, mm, ss = stamp:match('^(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)(%d%d)$')
      if y then
        bj = y .. '-' .. m .. '-' .. d .. ' ' .. hh .. ':' .. mm .. ':' .. ss .. ' CST'
      end
    end
    table.insert(out, {
      id = name,
      created_at_bj = bj,
    })
  end
  p:close()
  table.sort(out, function(a, b) return a.id > b.id end)
  return out
end

function _M.current(file_name)
  local ok, err = ensure_allowed(file_name)
  if not ok then
    return nil, err
  end
  local path = join(config_dir(), file_name)
  local content, read_err = read_file(path)
  if not content then
    return nil, 'read file failed: ' .. tostring(read_err)
  end
  return {
    file = file_name,
    content = content,
    path = path,
  }
end

function _M.history(file_name, limit)
  local ok, err = ensure_allowed(file_name)
  if not ok then
    return nil, err
  end
  local rows = list_versions(file_name)
  local max = tonumber(limit) or 50
  if max < #rows then
    local sliced = {}
    for i = 1, max do
      table.insert(sliced, rows[i])
    end
    rows = sliced
  end
  return {
    file = file_name,
    versions = rows,
  }
end

function _M.version(file_name, version_id)
  local ok, err = ensure_allowed(file_name)
  if not ok then
    return nil, err
  end
  if type(version_id) ~= 'string' or version_id == '' then
    return nil, 'version is required'
  end
  if version_id:find('%.%.', 1, true) then
    return nil, 'invalid version id'
  end
  local expected_prefix = file_name:gsub('%.yaml$', '') .. '__'
  if version_id:sub(1, #expected_prefix) ~= expected_prefix then
    return nil, 'version does not match file'
  end
  local path = join(versions_dir(), version_id)
  local content, read_err = read_file(path)
  if not content then
    return nil, 'read version failed: ' .. tostring(read_err)
  end
  return {
    file = file_name,
    version = version_id,
    content = content,
  }
end

function _M.save(file_name, content, operator)
  local ok, err = ensure_allowed(file_name)
  if not ok then
    return nil, err
  end
  if type(content) ~= 'string' or content == '' then
    return nil, 'content is required'
  end

  local ts = os.time()
  local path = join(config_dir(), file_name)
  local old_content, read_err = read_file(path)
  if not old_content then
    return nil, 'read current failed: ' .. tostring(read_err)
  end

  local write_ok, write_err = write_file_atomic(path, content)
  if not write_ok then
    return nil, write_err
  end

  local cfg, hash, load_err = loader.load()
  if not cfg then
    write_file_atomic(path, old_content)
    return nil, 'validation failed and rolled back: ' .. tostring(load_err)
  end

  runtime.set_config(cfg, hash)
  save_version_snapshot(file_name, content, ts, 'saved')

  return {
    file = file_name,
    config_hash = hash,
    saved_at_bj = now_bj(ts),
    operator = operator or 'admin',
  }
end

function _M.index_payload()
  local providers, providers_err = _M.current('providers.yaml')
  if not providers then
    return nil, providers_err
  end
  local models, models_err = _M.current('models.yaml')
  if not models then
    return nil, models_err
  end
  local p_hist = _M.history('providers.yaml', 30)
  local m_hist = _M.history('models.yaml', 30)

  return {
    editable = (os.getenv('GATEWAY_CONFIG_EDITABLE') or 'true') ~= 'false',
    timezone = 'Asia/Shanghai',
    files = {
      providers = {
        file = providers.file,
        content = providers.content,
        history = p_hist and p_hist.versions or {},
      },
      models = {
        file = models.file,
        content = models.content,
        history = m_hist and m_hist.versions or {},
      },
    },
    runtime = {
      config_hash = runtime.get_hash(),
    },
  }
end

function _M.encode(payload)
  return cjson.encode(payload)
end

return _M
