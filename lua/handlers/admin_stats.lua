local cjson = require('cjson.safe')
local stats = require('core.stats')
local admin_auth = require('core.admin_auth')

ngx.ctx.skip_stats = true

if not admin_auth.guard() then
  return
end

local args = ngx.req.get_uri_args()
local window_minutes = tonumber(args.window or args.window_minutes) or 60

local payload = stats.snapshot(window_minutes)
ngx.header['Content-Type'] = 'application/json'
ngx.say(cjson.encode(payload))
