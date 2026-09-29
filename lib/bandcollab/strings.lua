-- Key-based string tables. Text is looked up by key in the chosen language; a missing key
-- falls back to English, and a key missing everywhere shows as "[key]" so it is easy to spot.
-- Placeholders look like {name} and are filled from the vars table.
local M = {}

local Strings = {}
Strings.__index = Strings

M.FALLBACK = "en" -- used for keys missing in the chosen language
M.DEFAULT = "fi"  -- used when no language is chosen

-- new(tables, lang): tables is { fi = {...}, en = {...} }; nested tables flatten to dotted keys.
function M.new(tables, lang)
  local flat = {}
  local function flatten(prefix, t, into)
    for k, v in pairs(t) do
      local key = prefix == "" and k or (prefix .. "." .. k)
      if type(v) == "table" then flatten(key, v, into) else into[key] = v end
    end
  end
  for code, t in pairs(tables) do
    flat[code] = {}
    flatten("", t, flat[code])
  end
  return setmetatable({ flat = flat, lang = lang or M.DEFAULT }, Strings)
end

function Strings:has(key, lang)
  local t = self.flat[lang or self.lang]
  return t ~= nil and t[key] ~= nil
end

-- t(key [, vars]) -> string
function Strings:t(key, vars)
  local text = (self.flat[self.lang] or {})[key]
  if text == nil then text = (self.flat[M.FALLBACK] or {})[key] end
  if text == nil then return "[" .. key .. "]" end
  if vars then
    text = text:gsub("{([%w_]+)}", function(name)
      local v = vars[name]
      if v == nil then return "{" .. name .. "}" end
      return tostring(v)
    end)
  end
  return text
end

-- keys(lang) -> sorted list of every key defined in a language.
function Strings:keys(lang)
  local out = {}
  for k in pairs(self.flat[lang] or {}) do out[#out + 1] = k end
  table.sort(out)
  return out
end

-- languages() -> sorted list of language codes.
function Strings:languages()
  local out = {}
  for code in pairs(self.flat) do out[#out + 1] = code end
  table.sort(out)
  return out
end

-- load(dir, fs [, lang]) reads dir/<code>.lua files (each returns a table) through `load_file(path)`.
function M.load(dir, codes, load_file, lang)
  local tables = {}
  for _, code in ipairs(codes) do
    local chunk, err = load_file(dir .. "/" .. code .. ".lua")
    if not chunk then error("cannot load language " .. code .. ": " .. tostring(err), 0) end
    tables[code] = chunk()
  end
  return M.new(tables, lang)
end

return M
