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

local function read_status_and_headers(sock)
  local status_line, status_err = sock:receive('*l')
  if not status_line then
    return nil, nil, nil, nil, status_err
  end

  local http_version, status, reason = status_line:match('^(HTTP/%d+%.%d+)%s+(%d+)%s*(.*)$')
  if not status then
    return nil, nil, nil, nil, 'invalid status line'
  end

  local resp_headers = {}
  while true do
    local line, header_err = sock:receive('*l')
    if not line then
      return nil, nil, nil, nil, header_err
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

  return tonumber(status), reason, http_version, resp_headers, nil
end

local function open_socket_and_send(opts)
  if not opts or not opts.url then
    return nil, nil, 'missing url'
  end

  local parsed, err = parse_url(opts.url)
  if not parsed then
    return nil, nil, err
  end

  local sock = ngx.socket.tcp()
  if opts.timeout_ms then
    sock:settimeout(opts.timeout_ms)
    ngx.log(ngx.INFO, '[', format_timestamp(), '] [http_client] setting timeout: ', opts.timeout_ms, 'ms for url=', opts.url)
  end

  local ok, conn_err = sock:connect(parsed.host, parsed.port)
  if not ok then
    ngx.log(ngx.ERR, '[', format_timestamp(), '] [http_client] connection failed: url=', opts.url, ', host=', parsed.host, ', port=', parsed.port, ', error=', conn_err)
    return nil, nil, conn_err
  end

  if parsed.scheme == 'https' then
    local ssl_verify = opts.ssl_verify ~= false
    local ssl_ok, ssl_err = sock:sslhandshake(nil, parsed.host, ssl_verify)
    if not ssl_ok then
      ngx.log(ngx.ERR, '[', format_timestamp(), '] [http_client] SSL handshake failed: url=', opts.url, ', host=', parsed.host, ', ssl_verify=', ssl_verify, ', error=', ssl_err)
      sock:close()
      return nil, nil, ssl_err
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
    return nil, nil, send_err
  end

  if opts.body then
    local ok_body, body_err = sock:send(opts.body)
    if not ok_body then
      ngx.log(ngx.ERR, '[', format_timestamp(), '] [http_client] send body failed: url=', opts.url, ', body_size=', #opts.body, ', error=', body_err)
      sock:close()
      return nil, nil, body_err
    end
  end

  return sock, parsed, nil
end

function _M.request_stream(opts)
  local sock, _, err = open_socket_and_send(opts)
  if not sock then
    return nil, err
  end

  ngx.log(ngx.INFO, '[', format_timestamp(), '] [http_client] waiting for stream response: url=', opts.url)
  local status_num, reason, http_version, resp_headers, status_err = read_status_and_headers(sock)
  if not status_num then
    ngx.log(ngx.ERR, '[', format_timestamp(), '] [http_client] receive stream status failed: url=', opts.url, ', error=', status_err, ', timeout_ms=', opts.timeout_ms)
    sock:close()
    return nil, status_err
  end

  local method = opts.method or 'GET'
  local no_body = method == 'HEAD' or status_num == 204 or status_num == 304
  local transfer = resp_headers['transfer-encoding']
  local mode = 'until_eof'
  local fixed_remaining = nil
  local chunk_remaining = 0
  local chunk_done = false

  if no_body then
    mode = 'none'
  elseif transfer and transfer:lower():find('chunked', 1, true) then
    mode = 'chunked'
  else
    local length = tonumber(resp_headers['content-length'] or '')
    if length then
      mode = 'fixed'
      fixed_remaining = length
    end
  end

  local function read_chunk()
    if mode == 'none' then
      return nil
    end

    if mode == 'fixed' then
      if fixed_remaining <= 0 then
        return nil
      end
      local to_read = math.min(fixed_remaining, 8192)
      local data, read_err, partial = sock:receive(to_read)
      local out = data or partial
      if not out or #out == 0 then
        if read_err == 'closed' and fixed_remaining <= 0 then
          return nil
        end
        return nil, read_err or 'read fixed body failed'
      end
      fixed_remaining = fixed_remaining - #out
      return out
    end

    if mode == 'chunked' then
      if chunk_done then
        return nil
      end

      if chunk_remaining == 0 then
        local line, line_err = sock:receive('*l')
        if not line then
          return nil, line_err or 'read chunk size failed'
        end
        local size = tonumber(line:match('^[0-9a-fA-F]+'), 16)
        if not size then
          return nil, 'invalid chunk size'
        end
        if size == 0 then
          local trailer, trailer_err = sock:receive('*l')
          if not trailer and trailer_err then
            return nil, trailer_err
          end
          while true do
            local extra, extra_err = sock:receive('*l')
            if not extra then
              if extra_err == 'closed' then
                break
              end
              return nil, extra_err
            end
            if extra == '' then
              break
            end
          end
          chunk_done = true
          return nil
        end
        chunk_remaining = size
      end

      local to_read = math.min(chunk_remaining, 8192)
      local data, read_err, partial = sock:receive(to_read)
      local out = data or partial
      if not out or #out == 0 then
        return nil, read_err or 'read chunk data failed'
      end
      chunk_remaining = chunk_remaining - #out
      if chunk_remaining == 0 then
        local _, crlf_err = sock:receive(2)
        if crlf_err then
          return nil, crlf_err
        end
      end
      return out
    end

    local data, read_err, partial = sock:receive(8192)
    local out = data or partial
    if out and #out > 0 then
      return out
    end
    if read_err == 'closed' then
      return nil
    end
    return nil, read_err or 'read body failed'
  end

  local function read_all(max_bytes)
    local parts = {}
    local total = 0
    while true do
      local chunk, chunk_err = read_chunk()
      if chunk_err then
        return nil, chunk_err
      end
      if not chunk then
        break
      end
      total = total + #chunk
      if max_bytes and total > max_bytes then
        table.insert(parts, chunk:sub(1, max_bytes - (total - #chunk)))
        return table.concat(parts), 'body exceeds limit'
      end
      table.insert(parts, chunk)
    end
    return table.concat(parts), nil
  end

  local function close()
    return sock:close()
  end

  return {
    status = status_num,
    reason = reason,
    http_version = http_version,
    headers = resp_headers,
    read_chunk = read_chunk,
    read_all = read_all,
    close = close,
  }
end

function _M.request(opts)
  local sock, _, err = open_socket_and_send(opts)
  if not sock then
    return nil, err
  end

  ngx.log(ngx.INFO, '[', format_timestamp(), '] [http_client] waiting for response: url=', opts.url)
  local status_num, reason, http_version, resp_headers, status_err = read_status_and_headers(sock)
  if not status_num then
    ngx.log(ngx.ERR, '[', format_timestamp(), '] [http_client] receive status failed: url=', opts.url, ', error=', status_err, ', timeout_ms=', opts.timeout_ms)
    sock:close()
    return nil, status_err
  end

  local body = ''
  local method = opts.method or 'GET'
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
