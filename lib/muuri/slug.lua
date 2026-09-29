-- Safe internal names: lowercase ASCII, valid on Windows and Linux, unique
-- case-insensitively. The human-readable name is stored separately (in manifests).
local M = {}

local translit = {
  ["ä"] = "a", ["Ä"] = "a", ["ö"] = "o", ["Ö"] = "o", ["å"] = "a", ["Å"] = "a",
  ["é"] = "e", ["É"] = "e", ["è"] = "e", ["ü"] = "u", ["Ü"] = "u", ["ß"] = "ss",
  ["ø"] = "o", ["Ø"] = "o", ["æ"] = "ae", ["Æ"] = "ae", ["š"] = "s", ["Š"] = "s",
  ["ž"] = "z", ["Ž"] = "z", ["ñ"] = "n", ["ç"] = "c", ["á"] = "a", ["à"] = "a",
  ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["â"] = "a", ["ê"] = "e", ["ô"] = "o",
}

local reserved = { con = true, prn = true, aux = true, nul = true }
for i = 1, 9 do reserved["com" .. i] = true; reserved["lpt" .. i] = true end

M.DEFAULT_MAX = 40

local function is_reserved(name)
  -- Windows treats "con", "con.txt" and "CON" alike; slugs contain no dots, so the base is the whole name.
  return reserved[name] or reserved[name:match("^([^.]*)")]
end

-- slug(name [, max_length]) -> string; never empty, never Windows-reserved.
function M.slug(name, max_length)
  max_length = max_length or M.DEFAULT_MAX
  local out = {}
  for _, cp in utf8.codes(name, true) do
    local ch = utf8.char(cp)
    out[#out + 1] = translit[ch] or (cp < 128 and ch or "-")
  end
  local s = table.concat(out):lower()
  s = s:gsub("[^a-z0-9]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  if #s > max_length then s = s:sub(1, max_length):gsub("%-+$", "") end
  if s == "" then s = "untitled" end
  if is_reserved(s) then s = s .. "-x" end
  return s
end

-- unique(slug, taken) -> slug or slug-2, slug-3, ...; taken is a set (table) of existing names.
-- The comparison ignores case, so names that differ only by case are never both produced.
function M.unique(slug, taken)
  local lowered = {}
  for k in pairs(taken) do lowered[k:lower()] = true end
  if not lowered[slug:lower()] then return slug end
  local n = 2
  while lowered[(slug .. "-" .. n):lower()] do n = n + 1 end
  return slug .. "-" .. n
end

-- valid(name) -> true when the name already satisfies the slug rules.
function M.valid(name)
  return type(name) == "string" and name ~= "" and name:match("^[a-z0-9]+[a-z0-9-]*$") ~= nil
    and not name:match("%-$") and not is_reserved(name)
end

return M
