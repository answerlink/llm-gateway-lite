local runtime = require('config.runtime')
local loader = require('config.loader')
local stats = require('core.stats')

local function load_config()
  local cfg, hash, err = loader.load()
  if not cfg then
    ngx.log(ngx.ERR, 'config load failed: ', err or 'unknown error')
    return false
  end
  runtime.set_config(cfg, hash)
  ngx.log(ngx.INFO, 'config loaded: ', hash)
  return true
end

local phase = ngx.get_phase()
if phase == 'init' then
  local seed = math.floor(ngx.now() * 1000)
  math.randomseed(seed)
  load_config()
elseif phase == 'init_worker' then
  local seed = math.floor(ngx.now() * 1000) + (ngx.worker.id() or 0)
  math.randomseed(seed)
  stats.setup_snapshot_worker()
  local interval = runtime.reload_interval
  local function reload(premature)
    if premature then
      return
    end
    local cfg, hash, err = loader.load()
    if not cfg then
      ngx.log(ngx.ERR, 'config reload failed: ', err or 'unknown error')
      return
    end
    if hash ~= runtime.get_hash() then
      runtime.set_config(cfg, hash)
      ngx.log(ngx.INFO, 'config reloaded: ', hash)
    end
  end

  local ok, err = ngx.timer.every(interval, reload)
  if not ok then
    ngx.log(ngx.ERR, 'failed to start reload timer: ', err or 'unknown error')
  end
end
