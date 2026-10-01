-- The member's workspace on disk, and what state it is in relative to the band. Pure logic:
-- everything that touches REAPER lives in workspace.lua.
--
--   <proposals>/<member>/<library>/<cycle>/<song>/
--       work/         the workspace project, its media and the stems it plays
--       outbox/       frozen deliveries (d<timestamp>/)
--       backups/      the workspace as it was before each "get the latest" (b<timestamp>/)
local json = require("bandcollab.json")
local hash = require("bandcollab.hash")
local cycles = require("bandcollab.cycles")

local M = {}

M.SCHEMA = 1
M.STATE_FILE = "workspace.json"

-- dir(band, band_folder, member_id, song) -> the song's folder in the member's own proposals area
-- song = { library =, cycle =, slug = }
function M.dir(band, band_folder, member_id, song)
  local d = band_folder .. "/" .. band.locations.proposals .. "/" .. member_id .. "/" .. song.library
  if song.cycle then d = d .. "/" .. song.cycle end
  return d .. "/" .. song.slug
end

function M.work_dir(dir) return dir .. "/work" end
function M.outbox_dir(dir) return dir .. "/outbox" end
function M.backups_dir(dir) return dir .. "/backups" end
function M.project_file(dir, slug) return dir .. "/work/" .. slug .. ".rpp" end

-- read_state(fs, dir) -> state | nil   /   write_state(fs, dir, state) -> true | nil, err
function M.read_state(fs, dir)
  local text = fs.read_all(M.work_dir(dir) .. "/" .. M.STATE_FILE)
  local state = text and json.try_decode(text)
  if type(state) ~= "table" or state.schema ~= M.SCHEMA then return nil end
  return state
end

function M.write_state(fs, dir, state)
  state.schema = M.SCHEMA
  return fs.write_all(M.work_dir(dir) .. "/" .. M.STATE_FILE, json.encode(state, { pretty = true }) .. "\n")
end

-- Lines of a track chunk that change when the person merely looks around (selecting, resizing),
-- not when they change the music. They are left out of the fingerprint.
local VOLATILE = { "^%s*SEL%s", "^%s*TRACKHEIGHT%s", "^%s*SHOWINMIX%s", "^%s*VU%s", "^%s*FIXEDLANES%s", "^%s*LANEHEIGHT%s" }

-- normalize(chunk_text) -> the text without the volatile lines
function M.normalize(text)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local skip = false
    for _, pattern in ipairs(VOLATILE) do if line:match(pattern) then skip = true; break end end
    if not skip then out[#out + 1] = line end
  end
  return table.concat(out, "\n")
end

-- fingerprint(chunk_texts) -> hex; chunk_texts is the list of the member's own folder chunks, in order
function M.fingerprint(chunk_texts)
  local h = hash.new()
  for _, text in ipairs(chunk_texts) do h:feed(M.normalize(text)); h:feed("\0") end
  return h:finish()
end

-- sync_state(latest, state, current_fingerprint) -> { kind =, master_newer =, own_changed = }
--   latest: number of the newest usable publication (nil when there is none)
--   kind: "none" (all current), "down" (only the master is newer), "up" (only own changes),
--         "both" (fetch first, then propose)
-- Own changes are counted against what was last sent (or, before the first send, the base).
function M.sync_state(latest, state, current_fingerprint)
  local master_newer = latest ~= nil and latest > state.base_revision
  local reference = state.sent_fingerprint or state.own_fingerprint
  local own_changed = current_fingerprint ~= reference
  local kind = "none"
  if master_newer and own_changed then kind = "both"
  elseif master_newer then kind = "down"
  elseif own_changed then kind = "up" end
  return { kind = kind, master_newer = master_newer, own_changed = own_changed }
end

return M
