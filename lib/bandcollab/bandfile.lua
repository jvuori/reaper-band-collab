-- band.json: band-level settings shared by everyone through the band folder.
local json = require("bandcollab.json")

local M = {}

M.SCHEMA = 1
M.FILENAME = "band.json"

-- A library is a root for songs. "dated" libraries group songs into dated cycles (rehearsals);
-- "flat" libraries hold songs directly (official recordings).
M.LIBRARY_KINDS = { dated = true, flat = true }
M.DEFAULT_LIBRARIES = {
  { id = "rehearsals", label = "rehearsals", kind = "dated" },
  { id = "official", label = "official", kind = "flat" },
}

-- Errors are returned as (nil, code, detail). Codes have matching err.band_* messages in strings/.
--   band_unreadable, band_invalid, band_too_new

local function fail(code, detail) return nil, code, detail end

local function nonempty_string(v) return type(v) == "string" and v ~= "" end

-- validate(band) -> band | nil, code, detail
function M.validate(band)
  if type(band) ~= "table" then return fail("band_invalid", "not an object") end
  if math.type(band.schema) ~= "integer" then return fail("band_invalid", "schema") end
  if band.schema > M.SCHEMA then return fail("band_too_new", band.schema) end
  if band.schema < 1 then return fail("band_invalid", "schema") end
  if not nonempty_string(band.name) then return fail("band_invalid", "name") end
  if not nonempty_string(band.language) then return fail("band_invalid", "language") end

  if type(band.roles) ~= "table" or #band.roles == 0 then return fail("band_invalid", "roles") end
  local roles = {}
  for i, r in ipairs(band.roles) do
    if type(r) ~= "table" or not nonempty_string(r.id) or not nonempty_string(r.label) then
      return fail("band_invalid", "roles[" .. i .. "]")
    end
    if roles[r.id] then return fail("band_invalid", "duplicate role " .. r.id) end
    roles[r.id] = true
  end

  if type(band.members) ~= "table" or #band.members == 0 then return fail("band_invalid", "members") end
  local members, owned = {}, {}
  for i, m in ipairs(band.members) do
    if type(m) ~= "table" or not nonempty_string(m.id) or not nonempty_string(m.name) then
      return fail("band_invalid", "members[" .. i .. "]")
    end
    if members[m.id] then return fail("band_invalid", "duplicate member " .. m.id) end
    members[m.id] = true
    if type(m.roles) ~= "table" or #m.roles == 0 then return fail("band_invalid", "members[" .. i .. "].roles") end
    for _, rid in ipairs(m.roles) do
      if not roles[rid] then return fail("band_invalid", "unknown role " .. tostring(rid)) end
      if owned[rid] then return fail("band_invalid", "role " .. rid .. " has two owners") end
      owned[rid] = m.id
    end
  end

  if not nonempty_string(band.producer) or not members[band.producer] then
    return fail("band_invalid", "producer")
  end

  if band.libraries ~= nil then
    if type(band.libraries) ~= "table" or #band.libraries == 0 then return fail("band_invalid", "libraries") end
    local lib_ids = {}
    for i, l in ipairs(band.libraries) do
      if type(l) ~= "table" or not nonempty_string(l.id) or not nonempty_string(l.label) or not M.LIBRARY_KINDS[l.kind] then
        return fail("band_invalid", "libraries[" .. i .. "]")
      end
      if lib_ids[l.id] then return fail("band_invalid", "duplicate library " .. l.id) end
      lib_ids[l.id] = true
    end
  end

  local loc = band.locations
  if type(loc) ~= "table" then return fail("band_invalid", "locations") end
  for _, key in ipairs({ "master", "publications", "proposals" }) do
    if not nonempty_string(loc[key]) then return fail("band_invalid", "locations." .. key) end
  end
  return band
end

-- parse(text) -> band | nil, code, detail
function M.parse(text)
  local data, err = json.try_decode(text)
  if data == nil then return fail("band_invalid", err) end
  return M.validate(data)
end

-- read(fs, dir) -> band | nil, code, detail
function M.read(fs, dir)
  local text = fs.read_all(dir .. "/" .. M.FILENAME)
  if not text then return fail("band_unreadable", dir .. "/" .. M.FILENAME) end
  return M.parse(text)
end

-- write(fs, dir, band) -> true | nil, code, detail (the band is validated before anything is written)
function M.write(fs, dir, band)
  local ok, code, detail = M.validate(band)
  if not ok then return nil, code, detail end
  local written, err = fs.write_all(dir .. "/" .. M.FILENAME, json.encode(band, { pretty = true }) .. "\n")
  if not written then return fail("band_unreadable", err) end
  return true
end

-- libraries(band) -> list of { id, label, kind }; the defaults when band.json lists none.
function M.libraries(band) return band.libraries or M.DEFAULT_LIBRARIES end

-- library(band, id) -> library table | nil
function M.library(band, id)
  for _, l in ipairs(M.libraries(band)) do if l.id == id then return l end end
end

-- owner_of(band, role_id) -> member table | nil
function M.owner_of(band, role_id)
  for _, m in ipairs(band.members) do
    for _, rid in ipairs(m.roles) do
      if rid == role_id then return m end
    end
  end
end

-- roles_of(band, member_id) -> list of role tables in role order
function M.roles_of(band, member_id)
  local out = {}
  for _, m in ipairs(band.members) do
    if m.id == member_id then
      local wanted = {}
      for _, rid in ipairs(m.roles) do wanted[rid] = true end
      for _, r in ipairs(band.roles) do
        if wanted[r.id] then out[#out + 1] = r end
      end
    end
  end
  return out
end

return M
