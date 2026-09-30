-- song.json sits next to a song's project file and carries its identity, so the ID travels
-- with the folder when it is copied or moved.
local json = require("bandcollab.json")
local ids = require("bandcollab.ids")

local M = {}

M.SCHEMA = 1
M.FILENAME = "song.json"

-- read(fs, dir) -> table | nil   (nil when absent or unusable: the project then counts as new)
function M.read(fs, dir)
  local text = fs.read_all(dir .. "/" .. M.FILENAME)
  if not text then return nil end
  local data = json.try_decode(text)
  if type(data) ~= "table" or data.schema ~= M.SCHEMA or not ids.valid(data.id) then return nil end
  return data
end

function M.write(fs, dir, data)
  data.schema = M.SCHEMA
  return fs.write_all(dir .. "/" .. M.FILENAME, json.encode(data, { pretty = true }) .. "\n")
end

return M
