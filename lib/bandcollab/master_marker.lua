-- The visible "this is the master" banner: a region at the start of the master project, in REAPER's
-- own ruler. It works without the extension installed. Needs the REAPER API.
local pm = require("bandcollab.projectmodel")
local projects = require("bandcollab.projects")

local M = {}

M.LENGTH = 5 -- seconds the banner spans from the start of the project
local RED = 0x0000FF | 0x1000000

-- find(proj) -> index of the banner among the project's markers, or nil
function M.find(proj)
  local i = 0
  while true do
    local ret, _, _, _, _, number = reaper.EnumProjectMarkers2(proj, i)
    if not ret or ret == 0 then return nil end
    if number == pm.MASTER_MARKER_NUMBER then return i end
    i = i + 1
  end
end

-- ensure(fs, file, text) -> true | nil, err
-- Opens the master from its own file, adds the banner if it is missing (or updates its text),
-- saves, and closes the tab again. Safe to repeat.
function M.ensure(fs, file, text)
  if not fs.exists(file) then return nil, "no such project: " .. file end
  local original = (reaper.EnumProjects(-1))
  local proj = projects.open_bound(file)
  local index = M.find(proj)
  if index then
    reaper.SetProjectMarkerByIndex(proj, index, true, 0, M.LENGTH, pm.MASTER_MARKER_NUMBER, text, RED)
  else
    reaper.AddProjectMarker2(proj, true, 0, M.LENGTH, text, pm.MASTER_MARKER_NUMBER, RED)
  end
  projects.save_bound(proj)
  projects.close_tab(proj)
  projects.restore_selection(original)
  return true
end

return M
