local _M = {}

local function format_timestamp()
  local now = ngx.now()
  local sec = math.floor(now)
  local msec = math.floor((now - sec) * 1000)
  return os.date('%Y-%m-%d %H:%M:%S', sec) .. string.format('.%03d', msec)
end

local function parse_url(url)
  local scheme, rest = url:match('^(https?)://(.+)$')
  if not scheme then
    return nil, 'invalid url: ' .. tostring(url)
  end

  local host_port, path = rest:match('^([^/]+)(/.*)$')
  if not host_port then
    host_port = rest
    path = '/'
  end

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
    path = path,
    host_header = host_header,
  }
end

local function read_chunked(sock)
  local chunks = {}
  while true do
    local line, err = sock:receive('*l')
    if not line then
      return nil, err
    end
    local size = tonumber(line:match('^[0-9a-fA-F]+'), 16)
    if not size then
      return nil, 'invalid chunk size'
    end
    if size == 0 then
      local trailer = sock:receive('*l')
      if not trailer then
        return nil, 'invalid chunk trailer'
      end
      while true do
        local extra = sock:receive('*l')
        if not extra or extra == '' then
          break
        end
      end
      break
    end

    local data, err = sock:receive(size)
    if not data then
      return nil, err
    end
    table.insert(chunks, data)
    local crlf, err = sock:receive(2)
    if not crlf then
      return nil, err
    end
  end

  return table.concat(chunks)
end

function _M.request(opts)
  if not opts or not opts.url then
    return nil, 'missing url'
  end

  local parsed, err = parse_url(opts.url)
  if not parsed then
    return nil, err
  end

  local sock = ngx.socket.tcp()
  if opts.timeout_ms then
    sock:settimeout(opts.timeout_ms)
    ngx.log(ngx.INFO, '[', format_timestamp(), '] [http_client] setting timeout: ', opts.timeout_ms, 'ms for url=', opts.url)
  end

  local ok, conn_err = sock:connect(parsed.host, parsed.port)
  if not ok then
    ngx.log(ngx.ERR, '[', format_timestamp(), '] [http_client] connection failed: url=', opts.url, ', host=', parsed.host, ', port=', parsed.port, ', error=', conn_err)
    return nil, conn_err
  end

  if parsed.scheme == 'https' then
    local ssl_verify = opts.ssl_verify ~= false
    local ssl_ok, ssl_err = sock:sslhandshake(nil, parsed.host, ssl_verify)
    if not ssl_ok then
      ngx.log(ngx.ERR, '[', format_timestamp(), '] [http_client] SSL handshake failed: url=', opts.url, ', host=', parsed.host, ', ssl_verify=', ssl_verify, ', error=', ssl_err)
      sock:close()
      return nil, ssl_err
    end
  end

  local method = opts.method or 'GET'
  local headers = opts.headers or {}
  headers['Host'] = headers['Host'] or parsed.host_header
  headers['Connection'] = headers['Connection'] or 'close'

  if opts.body and not headers['Content-Length'] then
    headers['Content-Length'] = #opts.body
  end

  local lines = { method .. ' ' .. parsed.path .. ' HTTP/1.1' }
  for name, value in pairs(headers) do
    table.insert(lines, name .. ': ' .. tostring(value))
  end
  table.insert(lines, '')
  table.insert(lines, '')

  local request = table.concat(lines, '\r\n')
  local bytes, send_err = sock:send(request)
  if not bytes then
    ngx.log(ngx.ERR, '[', format_timestamp(), '] [http_client] send request failed: url=', opts.url, ', error=', send_err)
    sock:close()
    return nil, send_err
  end

  if opts.body then
    local ok_body, body_err = sock:send(opts.body)
    if not ok_body then
      ngx.log(ngx.ERR, '[', format_timestamp(), '] [http_client] send body failed: url=', opts.url, ', body_size=', #opts.body, ', error=', body_err)
      sock:close()
      return nil, body_err
    end
  end

  ngx.log(ngx.INFO, '[', format_timestamp(), '] [http_client] waiting for response: url=', opts.url)
  local status_line, status_err = sock:receive('*l')
  if not status_line then
    ngx.log(ngx.ERR, '[', format_timestamp(), '] [http_client] receive status line failed: url=', opts.url, ', error=', status_err, ', timeout_ms=', opts.timeout_ms)
    sock:close()
    return nil, status_err
  end
  ngx.log(ngx.INFO, '[', format_timestamp(), '] [http_client] received status line: ', status_line, ' for url=', opts.url)

  local http_version, status, reason = status_line:match('^(HTTP/%d+%.%d+)%s+(%d+)%s*(.*)$')
  if not status then
    sock:close()
    return nil, 'invalid status line'
  end

  local resp_headers = {}
  while true do
    local line, header_err = sock:receive('*l')
    if not line then
      sock:close()
      return nil, header_err
    end
    if line == '' then
      break
    end
    local name, value = line:match('^([^:]+):%s*(.*)$')
    if name then
      local key = name:lower()
      if resp_headers[key] then
        resp_headers[key] = resp_headers[key] .. ', ' .. value
      else
        resp_headers[key] = value
      end
    end
  end

  local body = ''
  local status_num = tonumber(status)
  if method ~= 'HEAD' and status_num ~= 204 and status_num ~= 304 then
    local transfer = resp_headers['transfer-encoding']
    if transfer and transfer:lower():find('chunked', 1, true) then
      local chunked, chunk_err = read_chunked(sock)
      if not chunked then
        sock:close()
        return nil, chunk_err
      end
      body = chunked
    else
      local length = tonumber(resp_headers['content-length'] or '')
      if length then
        local data, body_err = sock:receive(length)
        if not data then
          sock:close()
          return nil, body_err
        end
        body = data
      else
        local data, body_err = sock:receive('*a')
        if not data then
          sock:close()
          return nil, body_err
        end
        body = data
      end
    end
  end

  sock:close()

  return {
    status = status_num,
    reason = reason,
    http_version = http_version,
    headers = resp_headers,
    body = body,
  }
end

return _M
