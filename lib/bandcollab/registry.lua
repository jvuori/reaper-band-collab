-- The song registry: which songs exist and where they are. One file in the producer's area,
-- written only by the producer's tool. An entry is added LAST when a song is received, so an
-- interrupted receive never leaves a registered song without its files.
local json = require("bandcollab.json")

local M = {}

M.SCHEMA = 1
M.FILENAME = "registry.json"

-- file(band, band_folder) -> path of the registry file
function M.file(band, band_folder) return band_folder .. "/" .. band.locations.master .. "/" .. M.FILENAME end

function M.empty() return { schema = M.SCHEMA, songs = {} } end

-- load(fs, file) -> registry | nil, code   (a missing file is an empty registry)
function M.load(fs, file)
  local text = fs.read_all(file)
  if not text then return M.empty() end
  local reg = json.try_decode(text)
  if type(reg) ~= "table" or reg.schema ~= M.SCHEMA or type(reg.songs) ~= "table" then
    return nil, "registry_invalid"
  end
  return reg
end

-- save(fs, file, reg) -> true | nil, err. Written to a temporary file first, then moved into
-- place, so a crash or an early sync never leaves a half-written registry.
function M.save(fs, file, reg)
  local tmp = file .. ".tmp"
  local ok, err = fs.write_all(tmp, json.encode(reg, { pretty = true }) .. "\n")
  if not ok then return nil, err end
  if not fs.rename(tmp, file) then
    fs.remove(file) -- some systems refuse to replace an existing file
    if not fs.rename(tmp, file) then return nil, "cannot replace " .. file end
  end
  return true
end

function M.get(reg, id) return reg.songs[id] end

-- taken(reg) -> set of registered ids
function M.taken(reg)
  local out = {}
  for id in pairs(reg.songs) do out[id] = true end
  return out
end

-- put(reg, entry): adds or replaces the entry with entry.id
function M.put(reg, entry) reg.songs[entry.id] = entry end

-- find_by_source_hash(reg, hash) -> entry | nil: has a project with this exact content been received?
function M.find_by_source_hash(reg, hash)
  for _, e in pairs(reg.songs) do
    if e.source_hash == hash then return e end
  end
end

-- list(reg) -> entries sorted by library, cycle, then title
function M.list(reg)
  local out = {}
  for _, e in pairs(reg.songs) do out[#out + 1] = e end
  table.sort(out, function(a, b)
    if a.library ~= b.library then return a.library < b.library end
    if (a.cycle or "") ~= (b.cycle or "") then return (a.cycle or "") < (b.cycle or "") end
    return a.title:lower() < b.title:lower()
  end)
  return out
end

return M
