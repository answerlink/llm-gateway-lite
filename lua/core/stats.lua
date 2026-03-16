local cjson = require('cjson.safe')

local _M = {}

local DICT = ngx.shared.gateway_state
local PREFIX = 'stats:'
local MINUTE_PREFIX = PREFIX .. 'm:'
local MINUTE_TTL = 172800 -- 48h
local COOLDOWN_EVENT_TTL = 604800 -- 7d
local MAX_COOLDOWN_EVENTS = 200

local function incr(key, delta, init, ttl)
  local _, err = DICT:incr(key, delta, init or 0, ttl)
  if err then
    ngx.log(ngx.WARN, '[stats] incr failed key=', key, ', err=', err)
  end
end

local function get_number(key)
  local val = DICT:get(key)
  if type(val) ~= 'number' then
    return 0
  end
  return val
end

local function minute_key(minute, suffix)
  return MINUTE_PREFIX .. tostring(minute) .. ':' .. suffix
end

local function status_bucket(status_num)
  if type(status_num) ~= 'number' then
    return 'unknown'
  end
  if status_num >= 200 and status_num < 300 then
    return '2xx'
  end
  if status_num >= 300 and status_num < 400 then
    return '3xx'
  end
  if status_num >= 400 and status_num < 500 then
    return '4xx'
  end
  if status_num >= 500 and status_num < 600 then
    return '5xx'
  end
  return 'other'
end

local function sanitize_key(value)
  if type(value) ~= 'string' or value == '' then
    return nil
  end
  return value:gsub('[^%w%._%-]', '_')
end

local function key_suffix(provider, key_id, metric)
  return 'key:' .. provider .. ':' .. key_id .. ':' .. metric
end

local function set_scalar(key, value, ttl)
  if value == nil then
    return
  end
  local ok, err
  if ttl then
    ok, err = DICT:set(key, value, ttl)
  else
    ok, err = DICT:set(key, value)
  end
  if not ok then
    ngx.log(ngx.WARN, '[stats] set failed key=', key, ', err=', err)
  end
end

function _M.record(entry)
  if type(entry) ~= 'table' then
    return
  end

  local now_sec = math.floor(ngx.now())
  local status_num = tonumber(entry.upstream_status)
  local bucket = status_bucket(status_num)
  local is_success = status_num and status_num >= 200 and status_num < 400
  local minute = math.floor(ngx.now() / 60)

  incr(PREFIX .. 'total', 1, 0)
  incr(PREFIX .. 'status:' .. bucket, 1, 0)
  incr(minute_key(minute, 'total'), 1, 0, MINUTE_TTL)
  incr(minute_key(minute, 'status:' .. bucket), 1, 0, MINUTE_TTL)

  if is_success then
    incr(PREFIX .. 'success', 1, 0)
    incr(minute_key(minute, 'success'), 1, 0, MINUTE_TTL)
  else
    incr(PREFIX .. 'failure', 1, 0)
    incr(minute_key(minute, 'failure'), 1, 0, MINUTE_TTL)
  end

  local latency_ms = tonumber(entry.latency_ms)
  if latency_ms and latency_ms >= 0 then
    incr(PREFIX .. 'latency_sum_ms', latency_ms, 0)
    incr(PREFIX .. 'latency_count', 1, 0)
    incr(minute_key(minute, 'latency_sum_ms'), latency_ms, 0, MINUTE_TTL)
    incr(minute_key(minute, 'latency_count'), 1, 0, MINUTE_TTL)
  end

  local err_type = sanitize_key(entry.error_type)
  if err_type then
    incr(PREFIX .. 'error:' .. err_type, 1, 0)
  end

  local provider = sanitize_key(entry.provider)
  if provider then
    incr(PREFIX .. 'provider:' .. provider, 1, 0)
    if is_success then
      incr(PREFIX .. 'provider_success:' .. provider, 1, 0)
    else
      incr(PREFIX .. 'provider_failure:' .. provider, 1, 0)
    end
  end

  local key_id = sanitize_key(entry.key_id)
  if provider and key_id then
    incr(PREFIX .. key_suffix(provider, key_id, 'total'), 1, 0)
    incr(minute_key(minute, key_suffix(provider, key_id, 'total')), 1, 0, MINUTE_TTL)

    if is_success then
      incr(PREFIX .. key_suffix(provider, key_id, 'success'), 1, 0)
      incr(minute_key(minute, key_suffix(provider, key_id, 'success')), 1, 0, MINUTE_TTL)
    else
      incr(PREFIX .. key_suffix(provider, key_id, 'failure'), 1, 0)
      incr(minute_key(minute, key_suffix(provider, key_id, 'failure')), 1, 0, MINUTE_TTL)
    end

    if status_num and status_num >= 400 and status_num < 500 then
      incr(PREFIX .. key_suffix(provider, key_id, 'status_4xx'), 1, 0)
      incr(minute_key(minute, key_suffix(provider, key_id, 'status_4xx')), 1, 0, MINUTE_TTL)
      set_scalar(PREFIX .. key_suffix(provider, key_id, 'last_4xx_ts'), now_sec)
      set_scalar(PREFIX .. key_suffix(provider, key_id, 'last_4xx_status'), status_num)
      if err_type then
        set_scalar(PREFIX .. key_suffix(provider, key_id, 'last_4xx_error_type'), err_type)
      end
    end

    if status_num == 429 then
      incr(PREFIX .. key_suffix(provider, key_id, 'status_429'), 1, 0)
      incr(minute_key(minute, key_suffix(provider, key_id, 'status_429')), 1, 0, MINUTE_TTL)
    end
  end
end

function _M.record_key_cooldown(provider_name, key_id, ttl, opts)
  local provider = sanitize_key(provider_name)
  local key = sanitize_key(key_id)
  if not provider or not key then
    return
  end

  local now_sec = math.floor(ngx.now())
  local minute = math.floor(now_sec / 60)
  local ttl_num = tonumber(ttl) or 0
  local until_ts = now_sec + math.max(ttl_num, 0)

  incr(PREFIX .. key_suffix(provider, key, 'cooldown_count'), 1, 0)
  incr(minute_key(minute, key_suffix(provider, key, 'cooldown_count')), 1, 0, MINUTE_TTL)

  set_scalar(PREFIX .. key_suffix(provider, key, 'last_cooldown_ts'), now_sec)
  set_scalar(PREFIX .. key_suffix(provider, key, 'last_cooldown_until_ts'), until_ts)
  set_scalar(PREFIX .. key_suffix(provider, key, 'last_cooldown_ttl'), ttl_num)

  local status = opts and tonumber(opts.status) or nil
  local source = opts and sanitize_key(opts.source) or nil
  local reason = opts and sanitize_key(opts.reason) or nil
  if status then
    set_scalar(PREFIX .. key_suffix(provider, key, 'last_cooldown_status'), status)
  end
  if source then
    set_scalar(PREFIX .. key_suffix(provider, key, 'last_cooldown_source'), source)
  end
  if reason then
    set_scalar(PREFIX .. key_suffix(provider, key, 'last_cooldown_reason'), reason)
  end

  local seq, seq_err = DICT:incr(PREFIX .. 'cooldown_event_seq', 1, 0)
  if not seq then
    ngx.log(ngx.WARN, '[stats] cooldown event seq incr failed: ', seq_err)
    return
  end

  local event = {
    seq = seq,
    ts = now_sec,
    provider = provider,
    key_id = key,
    ttl = ttl_num,
    until_ts = until_ts,
    status = status,
    source = source,
    reason = reason,
  }

  set_scalar(PREFIX .. 'cooldown_event:' .. tostring(seq), cjson.encode(event), COOLDOWN_EVENT_TTL)
end

local function collect_prefix(prefix)
  local out = {}
  local keys = DICT:get_keys(0)
  for _, key in ipairs(keys) do
    if key:sub(1, #prefix) == prefix then
      local value = DICT:get(key)
      if type(value) == 'number' then
        out[key:sub(#prefix + 1)] = value
      end
    end
  end
  return out
end

local function build_key_stats(window, now_minute)
  local metrics = collect_prefix(PREFIX .. 'key:')
  local keys = {}

  for name, value in pairs(metrics) do
    local provider, key_id, metric = name:match('^([^:]+):([^:]+):([^:]+)$')
    if provider and key_id and metric then
      local id = provider .. ':' .. key_id
      if not keys[id] then
        keys[id] = {
          provider = provider,
          key_id = key_id,
          total = 0,
          success = 0,
          failure = 0,
          status_4xx = 0,
          status_429 = 0,
          cooldown_count = 0,
          window_total = 0,
          window_4xx = 0,
          window_429 = 0,
          window_cooldown_count = 0,
          current_cooldown_ttl = 0,
          last_4xx_ts = 0,
          last_4xx_status = 0,
          last_4xx_error_type = nil,
          last_cooldown_ts = 0,
          last_cooldown_until_ts = 0,
          last_cooldown_ttl = 0,
          last_cooldown_status = 0,
          last_cooldown_source = nil,
          last_cooldown_reason = nil,
        }
      end
      if keys[id][metric] ~= nil then
        keys[id][metric] = value
      end
    end
  end

  local out = {}
  for _, item in pairs(keys) do
    local p = item.provider
    local k = item.key_id

    for i = window - 1, 0, -1 do
      local m = now_minute - i
      item.window_total = item.window_total + get_number(minute_key(m, key_suffix(p, k, 'total')))
      item.window_4xx = item.window_4xx + get_number(minute_key(m, key_suffix(p, k, 'status_4xx')))
      item.window_429 = item.window_429 + get_number(minute_key(m, key_suffix(p, k, 'status_429')))
      item.window_cooldown_count = item.window_cooldown_count + get_number(minute_key(m, key_suffix(p, k, 'cooldown_count')))
    end

    local cooldown_ttl = DICT:ttl('cooldown:' .. p .. ':' .. k)
    if cooldown_ttl and cooldown_ttl > 0 then
      item.current_cooldown_ttl = math.floor(cooldown_ttl)
    end

    item.last_4xx_ts = get_number(PREFIX .. key_suffix(p, k, 'last_4xx_ts'))
    item.last_4xx_status = get_number(PREFIX .. key_suffix(p, k, 'last_4xx_status'))
    item.last_4xx_error_type = DICT:get(PREFIX .. key_suffix(p, k, 'last_4xx_error_type'))

    item.last_cooldown_ts = get_number(PREFIX .. key_suffix(p, k, 'last_cooldown_ts'))
    item.last_cooldown_until_ts = get_number(PREFIX .. key_suffix(p, k, 'last_cooldown_until_ts'))
    item.last_cooldown_ttl = get_number(PREFIX .. key_suffix(p, k, 'last_cooldown_ttl'))
    item.last_cooldown_status = get_number(PREFIX .. key_suffix(p, k, 'last_cooldown_status'))
    item.last_cooldown_source = DICT:get(PREFIX .. key_suffix(p, k, 'last_cooldown_source'))
    item.last_cooldown_reason = DICT:get(PREFIX .. key_suffix(p, k, 'last_cooldown_reason'))

    table.insert(out, item)
  end

  table.sort(out, function(a, b)
    if a.current_cooldown_ttl ~= b.current_cooldown_ttl then
      return a.current_cooldown_ttl > b.current_cooldown_ttl
    end
    if a.window_4xx ~= b.window_4xx then
      return a.window_4xx > b.window_4xx
    end
    if a.window_cooldown_count ~= b.window_cooldown_count then
      return a.window_cooldown_count > b.window_cooldown_count
    end
    return a.total > b.total
  end)

  return out
end

local function build_cooldown_events()
  local rows = {}
  local keys = DICT:get_keys(0)
  local prefix = PREFIX .. 'cooldown_event:'

  for _, key in ipairs(keys) do
    if key:sub(1, #prefix) == prefix then
      local seq = tonumber(key:sub(#prefix + 1)) or 0
      local payload = DICT:get(key)
      if type(payload) == 'string' then
        local decoded = cjson.decode(payload)
        if type(decoded) == 'table' then
          decoded.seq = seq
          table.insert(rows, decoded)
        end
      end
    end
  end

  table.sort(rows, function(a, b)
    return (a.seq or 0) > (b.seq or 0)
  end)

  if #rows > MAX_COOLDOWN_EVENTS then
    local trimmed = {}
    for i = 1, MAX_COOLDOWN_EVENTS do
      trimmed[i] = rows[i]
    end
    return trimmed
  end

  return rows
end

function _M.snapshot(window_minutes)
  local window = tonumber(window_minutes) or 60
  if window < 5 then
    window = 5
  end
  if window > 1440 then
    window = 1440
  end

  local now = math.floor(ngx.now())
  local now_minute = math.floor(now / 60)

  local totals = {
    total = get_number(PREFIX .. 'total'),
    success = get_number(PREFIX .. 'success'),
    failure = get_number(PREFIX .. 'failure'),
    latency_sum_ms = get_number(PREFIX .. 'latency_sum_ms'),
    latency_count = get_number(PREFIX .. 'latency_count'),
    by_status = {
      ['2xx'] = get_number(PREFIX .. 'status:2xx'),
      ['3xx'] = get_number(PREFIX .. 'status:3xx'),
      ['4xx'] = get_number(PREFIX .. 'status:4xx'),
      ['5xx'] = get_number(PREFIX .. 'status:5xx'),
      unknown = get_number(PREFIX .. 'status:unknown'),
      other = get_number(PREFIX .. 'status:other'),
    },
    by_error_type = collect_prefix(PREFIX .. 'error:'),
    by_provider = collect_prefix(PREFIX .. 'provider:'),
    by_provider_success = collect_prefix(PREFIX .. 'provider_success:'),
    by_provider_failure = collect_prefix(PREFIX .. 'provider_failure:'),
  }

  local avg_latency_ms = 0
  if totals.latency_count > 0 then
    avg_latency_ms = math.floor((totals.latency_sum_ms / totals.latency_count) * 100) / 100
  end
  totals.avg_latency_ms = avg_latency_ms

  local success_rate = 0
  if totals.total > 0 then
    success_rate = math.floor((totals.success / totals.total) * 10000) / 100
  end

  local series = {}
  for i = window - 1, 0, -1 do
    local m = now_minute - i
    local minute_total = get_number(minute_key(m, 'total'))
    local minute_success = get_number(minute_key(m, 'success'))
    local minute_failure = get_number(minute_key(m, 'failure'))
    local minute_latency_count = get_number(minute_key(m, 'latency_count'))
    local minute_latency_sum_ms = get_number(minute_key(m, 'latency_sum_ms'))
    local minute_avg_latency_ms = 0
    if minute_latency_count > 0 then
      minute_avg_latency_ms = math.floor((minute_latency_sum_ms / minute_latency_count) * 100) / 100
    end

    table.insert(series, {
      ts = m * 60,
      total = minute_total,
      success = minute_success,
      failure = minute_failure,
      avg_latency_ms = minute_avg_latency_ms,
      status_2xx = get_number(minute_key(m, 'status:2xx')),
      status_4xx = get_number(minute_key(m, 'status:4xx')),
      status_5xx = get_number(minute_key(m, 'status:5xx')),
    })
  end

  local key_stats = build_key_stats(window, now_minute)
  local cooldown_events = build_cooldown_events()

  return {
    now = now,
    window_minutes = window,
    totals = totals,
    success_rate = success_rate,
    series = series,
    key_stats = key_stats,
    cooldown_events = cooldown_events,
  }
end

return _M
