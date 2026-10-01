-- The REAPER side of the guardian: which project tabs are open, and what hidden marker each carries.
local pm = require("bandcollab.projectmodel")

local M = {}

-- projects() -> { { handle =, file =, marker_kind = }, ... } for every open tab (unsaved tabs have no file)
function M.projects()
  local out = {}
  local i = 0
  while true do
    local proj, file = reaper.EnumProjects(i, "")
    if not proj then break end
    out[#out + 1] = { handle = proj, file = file ~= "" and file or nil, marker_kind = pm.get_project_marker(proj, pm.KEY_KIND) }
    i = i + 1
  end
  return out
end

return M
