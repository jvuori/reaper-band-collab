-- First-run logic: which band folder is this machine using, and who is the person at the keyboard.
-- The answers are stored per machine (see localsettings.lua). No drawing here; ui/ does that.
local bandfile = require("bandcollab.bandfile")
local path = require("bandcollab.path")

local M = {}

-- folder_from_file(file) -> the folder containing the file the user picked.
-- Members are asked to pick band.json inside the band folder; that is easier than browsing
-- for a folder, and picking the wrong file is caught by check_folder.
function M.folder_from_file(file) return path.dirname(file) end

-- check_folder(fs, folder) -> band | nil, code, detail
-- A folder is a band folder only when it holds a valid band.json.
function M.check_folder(fs, folder)
  if not folder or folder == "" then return nil, "band_unreadable", "" end
  return bandfile.read(fs, folder)
end

-- member_choices(band) -> list of { id =, name =, roles = "Basso, Rummut" } for "Kuka sinä olet?"
function M.member_choices(band)
  local out = {}
  for _, m in ipairs(band.members) do
    local labels = {}
    for _, r in ipairs(bandfile.roles_of(band, m.id)) do labels[#labels + 1] = r.label end
    out[#out + 1] = { id = m.id, name = m.name, roles = table.concat(labels, ", ") }
  end
  return out
end

-- complete(settings, band, folder, member_id) -> true | nil, code
-- Stores the answers only when the member really is in the band.
function M.complete(settings, band, folder, member_id)
  local known = false
  for _, m in ipairs(band.members) do if m.id == member_id then known = true end end
  if not known then return nil, "firstrun_unknown_member" end
  settings:set_band_folder(folder)
  settings:set_member(member_id)
  return true
end

-- current(settings, fs) -> band, member_id | nil, code
-- Checks a stored configuration still makes sense (the folder may have moved or been deleted).
function M.current(settings, fs)
  if not settings:is_configured() then return nil, "firstrun_needed" end
  local band, code, detail = M.check_folder(fs, settings:band_folder())
  if not band then return nil, code, detail end
  local member = settings:member()
  for _, m in ipairs(band.members) do if m.id == member then return band, member end end
  return nil, "firstrun_unknown_member"
end

return M
