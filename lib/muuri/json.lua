-- Dependency-free JSON encoder/decoder.
-- Encoding is deterministic (object keys sorted, fixed number formatting) so manifests
-- are stable and diffable. Decoding reports the line and column of the first error.
local M = {}

M.null = setmetatable({}, { __tostring = function() return "json.null" end })
local array_mt = { __jsonarray = true }

-- Marks a table as a JSON array (needed for empty arrays, which would otherwise encode as {}).
function M.array(t) return setmetatable(t or {}, array_mt) end

local escapes = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encode_string(s)
  if not utf8.len(s) then error("json: string is not valid UTF-8", 0) end
  return '"' .. s:gsub('[%c"\\]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function is_array(t)
  if getmetatable(t) == array_mt then return true end
  if next(t) == nil then return false end
  local n = 0
  for k in pairs(t) do
    if math.type(k) ~= "integer" or k < 1 then return false end
    n = n + 1
  end
  return n == #t
end

local function encode_number(n)
  if n ~= n or n == math.huge or n == -math.huge then error("json: cannot encode NaN or infinity", 0) end
  if math.type(n) == "integer" then return string.format("%d", n) end
  if n == math.floor(n) and math.abs(n) < 2^53 then return string.format("%d", n) end
  return string.format("%.14g", n)
end

local function encode_value(v, indent, level, out)
  local t = type(v)
  if v == M.null then out[#out + 1] = "null"
  elseif t == "nil" then out[#out + 1] = "null"
  elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
  elseif t == "number" then out[#out + 1] = encode_number(v)
  elseif t == "string" then out[#out + 1] = encode_string(v)
  elseif t == "table" then
    local nl = indent and ("\n" .. string.rep(indent, level + 1)) or ""
    local nl_end = indent and ("\n" .. string.rep(indent, level)) or ""
    local sep = indent and ": " or ":"
    if is_array(v) then
      if #v == 0 then out[#out + 1] = "[]"; return end
      out[#out + 1] = "["
      for i = 1, #v do
        out[#out + 1] = (i > 1 and "," or "") .. nl
        encode_value(v[i], indent, level + 1, out)
      end
      out[#out + 1] = nl_end .. "]"
    else
      local keys = {}
      for k in pairs(v) do
        if type(k) ~= "string" then error("json: object keys must be strings", 0) end
        keys[#keys + 1] = k
      end
      if #keys == 0 then out[#out + 1] = "{}"; return end
      table.sort(keys)
      out[#out + 1] = "{"
      for i, k in ipairs(keys) do
        out[#out + 1] = (i > 1 and "," or "") .. nl .. encode_string(k) .. sep
        encode_value(v[k], indent, level + 1, out)
      end
      out[#out + 1] = nl_end .. "}"
    end
  else
    error("json: cannot encode a value of type " .. t, 0)
  end
end

-- json.encode(value [, {pretty = true}]) -> string
function M.encode(value, opts)
  local out = {}
  encode_value(value, (opts and opts.pretty) and "  " or nil, 0, out)
  return table.concat(out)
end

---------------------------------------------------------------------------- decoding

local function fail(s, pos, msg)
  local line, col = 1, 1
  for i = 1, pos - 1 do
    if s:byte(i) == 10 then line, col = line + 1, 1 else col = col + 1 end
  end
  error(string.format("json: %s at line %d, column %d", msg, line, col), 0)
end

local function skip_ws(s, pos)
  return s:match("^[ \t\r\n]*()", pos)
end

local parse_value

local function parse_string(s, pos)
  local i = pos + 1
  local parts = {}
  while true do
    local j = s:find('["\\%c]', i)
    if not j then fail(s, pos, "unterminated string") end
    local c = s:sub(j, j)
    parts[#parts + 1] = s:sub(i, j - 1)
    if c == '"' then
      local str = table.concat(parts)
      if not utf8.len(str) then fail(s, pos, "invalid UTF-8 in string") end
      return str, j + 1
    elseif c == "\\" then
      local e = s:sub(j + 1, j + 1)
      local simple = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
      if simple[e] then
        parts[#parts + 1] = simple[e]; i = j + 2
      elseif e == "u" then
        local hex = s:match("^%x%x%x%x", j + 2)
        if not hex then fail(s, j, "invalid \\u escape") end
        local cp = tonumber(hex, 16)
        i = j + 6
        if cp >= 0xD800 and cp <= 0xDBFF then
          local low = s:match("^\\u(%x%x%x%x)", i)
          local lowcp = low and tonumber(low, 16)
          if not lowcp or lowcp < 0xDC00 or lowcp > 0xDFFF then fail(s, j, "unpaired surrogate") end
          cp = 0x10000 + ((cp - 0xD800) << 10) + (lowcp - 0xDC00)
          i = i + 6
        elseif cp >= 0xDC00 and cp <= 0xDFFF then
          fail(s, j, "unpaired surrogate")
        end
        parts[#parts + 1] = utf8.char(cp)
      else
        fail(s, j, "invalid escape sequence")
      end
    else
      fail(s, j, "control character in string")
    end
  end
end

local function parse_number(s, pos)
  local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
  local int = s:match("^-?%d+", pos)
  if not int or (int:match("^-?0%d")) then fail(s, pos, "invalid number") end
  local text = s:match("^-?%d+%.%d+[eE][+-]?%d+", pos) or s:match("^-?%d+[eE][+-]?%d+", pos)
    or s:match("^-?%d+%.%d+", pos) or int
  local n = tonumber(text)
  if not n then fail(s, pos, "invalid number") end
  if text:match("^-?%d+$") then n = math.tointeger(n) or n end
  return n, pos + #text
end

local function parse_array(s, pos)
  local arr = M.array()
  pos = skip_ws(s, pos + 1)
  if s:sub(pos, pos) == "]" then return arr, pos + 1 end
  while true do
    local v
    v, pos = parse_value(s, pos)
    arr[#arr + 1] = v
    pos = skip_ws(s, pos)
    local c = s:sub(pos, pos)
    if c == "," then pos = skip_ws(s, pos + 1)
    elseif c == "]" then return arr, pos + 1
    else fail(s, pos, "expected ',' or ']'") end
  end
end

local function parse_object(s, pos)
  local obj = {}
  pos = skip_ws(s, pos + 1)
  if s:sub(pos, pos) == "}" then return obj, pos + 1 end
  while true do
    if s:sub(pos, pos) ~= '"' then fail(s, pos, "expected a string key") end
    local k
    k, pos = parse_string(s, pos)
    pos = skip_ws(s, pos)
    if s:sub(pos, pos) ~= ":" then fail(s, pos, "expected ':'") end
    local v
    v, pos = parse_value(s, skip_ws(s, pos + 1))
    obj[k] = v
    pos = skip_ws(s, pos)
    local c = s:sub(pos, pos)
    if c == "," then pos = skip_ws(s, pos + 1)
    elseif c == "}" then return obj, pos + 1
    else fail(s, pos, "expected ',' or '}'") end
  end
end

function parse_value(s, pos)
  local c = s:sub(pos, pos)
  if c == "{" then return parse_object(s, pos)
  elseif c == "[" then return parse_array(s, pos)
  elseif c == '"' then return parse_string(s, pos)
  elseif c == "-" or c:match("%d") then return parse_number(s, pos)
  elseif s:sub(pos, pos + 3) == "true" then return true, pos + 4
  elseif s:sub(pos, pos + 4) == "false" then return false, pos + 5
  elseif s:sub(pos, pos + 3) == "null" then return M.null, pos + 4
  elseif c == "" then fail(s, pos, "unexpected end of input")
  else fail(s, pos, "unexpected character '" .. c .. "'") end
end

-- json.decode(text) -> value; raises an error string on malformed input.
-- Use json.try_decode for a (value | nil, message) result.
function M.decode(s)
  if type(s) ~= "string" then error("json: decode expects a string", 0) end
  if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end -- skip a UTF-8 byte order mark
  local v, pos = parse_value(s, skip_ws(s, 1))
  pos = skip_ws(s, pos)
  if pos <= #s then fail(s, pos, "unexpected data after the value") end
  return v
end

function M.try_decode(s)
  local ok, res = pcall(M.decode, s)
  if ok then return res end
  return nil, res
end

return M
