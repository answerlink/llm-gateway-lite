local _M = {}

local function trim(value)
  return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function unquote(value)
  if not value then
    return value
  end
  if #value < 2 then
    return value
  end
  local first = value:sub(1, 1)
  local last = value:sub(-1)
  if (first == '"' and last == '"') or (first == "'" and last == "'") then
    local inner = value:sub(2, -2)
    if first == '"' then
      inner = inner:gsub('\\\\', '\\')
      inner = inner:gsub('\\"', '"')
      inner = inner:gsub('\\n', '\n')
      inner = inner:gsub('\\r', '\r')
      inner = inner:gsub('\\t', '\t')
    else
      inner = inner:gsub("''", "'")
    end
    return inner
  end
  return value
end

local function parse_scalar(value)
  local raw = trim(value or '')
  if raw == '' then
    return ''
  end

  local first = raw:sub(1, 1)
  local last = raw:sub(-1)
  if (first == '"' and last == '"') or (first == "'" and last == "'") then
    return unquote(raw)
  end

  local lower = raw:lower()
  if lower == 'null' or lower == '~' then
    return nil
  end
  if lower == 'true' then
    return true
  end
  if lower == 'false' then
    return false
  end
  if raw:match('^[-+]?%d+$') then
    return tonumber(raw)
  end
  if raw:match('^[-+]?%d+%.%d+$') then
    return tonumber(raw)
  end
  return raw
end

local function strip_comment(line)
  local in_single = false
  local in_double = false
  for i = 1, #line do
    local ch = line:sub(i, i)
    if ch == "'" and not in_double then
      in_single = not in_single
    elseif ch == '"' and not in_single then
      in_double = not in_double
    elseif ch == '#' and not in_single and not in_double then
      return line:sub(1, i - 1)
    end
  end
  return line
end

function _M.decode(text)
  if type(text) ~= 'string' then
    return nil, 'invalid yaml input'
  end

  local root = {}
  local stack = { { indent = -1, container = root, kind = 'map' } }

  for raw_line in text:gmatch('([^\r\n]+)') do
    local line = strip_comment(raw_line)
    if not line:match('^%s*$') then
      local indent = line:match('^(%s*)')
      local indent_len = #indent
      local content = line:sub(indent_len + 1)

      while indent_len <= stack[#stack].indent do
        table.remove(stack)
      end

      local parent = stack[#stack]
      if parent.kind == 'auto' then
        if content:match('^%-') then
          parent.kind = 'seq'
        else
          parent.kind = 'map'
        end
      end

      if content:match('^%-') then
        if parent.kind ~= 'seq' then
          return nil, 'sequence item in map: ' .. raw_line
        end
        local item = trim(content:sub(2))
        if item == '' then
          local node = {}
          table.insert(parent.container, node)
          table.insert(stack, { indent = indent_len, container = node, kind = 'auto' })
        else
          local key, value = item:match('^([^:]+):(.*)$')
          if key then
            local node = {}
            local trimmed_key = trim(key)
            local rest = trim(value or '')
            if rest == '' then
              node[unquote(trimmed_key)] = {}
              table.insert(parent.container, node)
              table.insert(stack, { indent = indent_len, container = node[unquote(trimmed_key)], kind = 'auto' })
            else
              node[unquote(trimmed_key)] = parse_scalar(rest)
              table.insert(parent.container, node)
              table.insert(stack, { indent = indent_len, container = node, kind = 'map' })
            end
          else
            table.insert(parent.container, parse_scalar(item))
          end
        end
      else
        if parent.kind == 'seq' then
          return nil, 'mapping item in sequence: ' .. raw_line
        end
        local key, value = content:match('^([^:]+):(.*)$')
        if not key then
          return nil, 'invalid line: ' .. raw_line
        end
        local trimmed_key = trim(key)
        local rest = trim(value or '')
        if rest == '' then
          local node = {}
          parent.container[unquote(trimmed_key)] = node
          table.insert(stack, { indent = indent_len, container = node, kind = 'auto' })
        else
          parent.container[unquote(trimmed_key)] = parse_scalar(rest)
        end
      end
    end
  end

  return root
end

return _M
