-- Reads and writes the band structure in a REAPER project (needs the REAPER API).
-- Role folders carry hidden markers in track extended state, so names are display labels only
-- and renaming a folder never changes who owns it.
local folders = require("bandcollab.folders")

local M = {}

M.KEY_ROLE = "bandcollab_role"   -- role id, on the role's folder track
M.KEY_OWNER = "bandcollab_owner" -- member id at the time the folder was created
M.SECTION = "bandcollab"         -- project-level extended state section
M.MEDIA_DIR = "media"            -- recording path, relative to the project

function M.set_marker(track, key, value)
  reaper.GetSetMediaTrackInfo_String(track, "P_EXT:" .. key, value, true)
end

function M.get_marker(track, key)
  local ok, value = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:" .. key, "", false)
  if ok and value ~= "" then return value end
  return nil
end

local function native(color) return reaper.ColorToNative(color[1], color[2], color[3]) | 0x1000000 end

-- clear(proj): delete every track of the project.
function M.clear(proj)
  for i = reaper.CountTracks(proj) - 1, 0, -1 do reaper.DeleteTrack(reaper.GetTrack(proj, i)) end
end

-- apply_plan(proj, plan) -> list of track handles. Appends the planned tracks to the project.
function M.apply_plan(proj, plan)
  local tracks = {}
  local base = reaper.CountTracks(proj)
  for i, e in ipairs(plan) do
    reaper.InsertTrackAtIndex(base + i - 1, false)
    local tr = reaper.GetTrack(proj, base + i - 1)
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", e.name, true)
    reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", e.depth)
    if e.color then reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", native(e.color)) end
    if e.kind == "folder" then
      M.set_marker(tr, M.KEY_ROLE, e.role)
      if e.owner then M.set_marker(tr, M.KEY_OWNER, e.owner) end
    end
    tracks[i] = tr
  end
  return tracks
end

-- set_recording_path(proj): recordings go to a folder inside the project, so a copied or moved
-- project folder is self-contained.
function M.set_recording_path(proj)
  reaper.GetSetProjectInfo_String(proj, "RECORD_PATH", M.MEDIA_DIR, true)
end

function M.recording_path(proj)
  local _, path = reaper.GetSetProjectInfo_String(proj, "RECORD_PATH", "", false)
  return path
end

-- depths(proj) -> array of I_FOLDERDEPTH values in track order
function M.depths(proj)
  local out = {}
  for i = 0, reaper.CountTracks(proj) - 1 do
    out[i + 1] = math.floor(reaper.GetMediaTrackInfo_Value(reaper.GetTrack(proj, i), "I_FOLDERDEPTH"))
  end
  return out
end

-- role_folders(proj) -> list, in project order, of top-level folders that carry a role marker:
--   { role =, owner =, track =, index = (1-based), last = (1-based), name =, children = count }
function M.role_folders(proj)
  local depths = M.depths(proj)
  local out = {}
  for _, f in ipairs(folders.top_level(depths)) do
    local tr = reaper.GetTrack(proj, f.first - 1)
    local role = M.get_marker(tr, M.KEY_ROLE)
    if role then
      local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
      out[#out + 1] = {
        role = role, owner = M.get_marker(tr, M.KEY_OWNER), track = tr,
        index = f.first, last = f.last, name = name, children = f.last - f.first,
      }
    end
  end
  return out
end

-- role_of_track(proj, track) -> role id of the role folder containing the track, or nil
function M.role_of_track(proj, track)
  local index = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  local f = folders.folder_of(M.depths(proj), index)
  if not f then return nil end
  return M.get_marker(reaper.GetTrack(proj, f.first - 1), M.KEY_ROLE)
end

-- owned_folders(proj, band, member_id) -> role folders whose role belongs to the member.
-- band.json is authoritative for ownership, not the owner marker stored on the folder.
function M.owned_folders(proj, band, member_id)
  local bandfile = require("bandcollab.bandfile")
  local mine = {}
  for _, r in ipairs(bandfile.roles_of(band, member_id)) do mine[r.id] = true end
  local out = {}
  for _, f in ipairs(M.role_folders(proj)) do
    if mine[f.role] then out[#out + 1] = f end
  end
  return out
end

-- Project-level markers: what kind of managed project this is, and for which band.
M.KEY_KIND = "kind"          -- "template" or "song"
M.KEY_BAND = "band_name"

function M.set_project_marker(proj, key, value) reaper.SetProjExtState(proj, M.SECTION, key, value) end

function M.get_project_marker(proj, key)
  local ok, value = reaper.GetProjExtState(proj, M.SECTION, key)
  if ok ~= 0 and value ~= "" then return value end
  return nil
end

return M
