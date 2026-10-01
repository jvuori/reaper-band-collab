-- "Enable band guardian" / "Disable band guardian": puts the start-up block into (or takes it out
-- of) REAPER's __startup.lua. Takes the file system and the file as arguments, so it can be tested.
local startup_block = require("bandcollab.startup_block")

local M = {}

-- startup_file(resource_path) -> where REAPER looks for the start-up script
function M.startup_file(resource_path) return resource_path .. "/Scripts/__startup.lua" end

-- enable(fs, file, script_path) -> true | nil, err
function M.enable(fs, file, script_path)
  local text = fs.read_all(file) or ""
  return fs.write_all(file, startup_block.install(text, script_path))
end

-- disable(fs, file) -> true | nil, err; the file is removed when nothing of the user's is left in it
function M.disable(fs, file)
  local text = fs.read_all(file)
  if not text then return true end
  local rest = startup_block.remove(text)
  if rest:match("^%s*$") then fs.remove(file); return true end
  return fs.write_all(file, rest)
end

function M.enabled(fs, file) return startup_block.has(fs.read_all(file) or "") end

return M
