-- The producer's inbox: proposals (deliveries) the members have sent, per song, with who sent them,
-- when, their note, and whether they were made against an older version of the master.
-- Only a member's newest complete delivery for a song counts; older ones are superseded.
local deliveries = require("bandcollab.deliveries")
local revisions = require("bandcollab.revisions")
local cycles = require("bandcollab.cycles")
local bandfile = require("bandcollab.bandfile")
local wm = require("bandcollab.workspace_model")
local json = require("bandcollab.json")

local M = {}

local function subfolders(fs, dir)
  local out = {}
  for _, e in ipairs(fs.list(dir) or {}) do if e.is_dir then out[#out + 1] = e.name end end
  return out
end

local function display_time(iso) return (iso or ""):sub(1, 16):gsub("T", " ") end

-- list(fs, band, band_folder) -> { pending = {...}, accepted = {...}, arriving = {...} }
-- entry = { member, member_name, library, cycle, slug, title, delivery, dir, sent, sent_iso, note,
--           base, current, outdated, status, superseded, song_id }
--   arriving: songs where a member's newest delivery is still being copied (no completion marker)
function M.list(fs, band, band_folder)
  local pending, accepted, arriving = {}, {}, {}
  for _, member in ipairs(band.members) do
    local member_root = band_folder .. "/" .. band.locations.proposals .. "/" .. member.id
    for _, lib in ipairs(bandfile.libraries(band)) do
      local places = {}
      if lib.kind == "dated" then
        for _, name in ipairs(subfolders(fs, member_root .. "/" .. lib.id)) do
          if cycles.valid_date(name) then places[#places + 1] = { cycle = name, dir = member_root .. "/" .. lib.id .. "/" .. name } end
        end
      else
        places[1] = { cycle = nil, dir = member_root .. "/" .. lib.id }
      end
      for _, place in ipairs(places) do
        for _, slug in ipairs(subfolders(fs, place.dir)) do
          local song_dir = place.dir .. "/" .. slug
          local list = deliveries.list(fs, wm.outbox_dir(song_dir))
          if #list > 0 then
            local song = { member = member.id, member_name = member.name, library = lib.id, cycle = place.cycle, slug = slug }
            local pub_dir = cycles.dir(band, band_folder, "publications", lib.id, place.cycle) .. "/" .. slug
            local latest = deliveries.latest(fs, wm.outbox_dir(song_dir))
            local newest = list[#list]
            if not newest.complete and (not latest or newest.id > latest.id) then
              arriving[#arriving + 1] = { member = member.id, member_name = member.name, slug = slug, delivery = newest.id }
            end
            if latest then
              local info = deliveries.read(fs, latest.dir) or {}
              local current = revisions.latest(fs, pub_dir)
              local complete_count = 0
              for _, d in ipairs(list) do if d.complete then complete_count = complete_count + 1 end end
              local status = deliveries.status(fs, pub_dir, latest.id)
              local entry = {
                member = song.member, member_name = song.member_name, library = lib.id, cycle = place.cycle, slug = slug,
                title = info.song and info.song.title or slug, song_id = info.song and info.song.id,
                delivery = latest.id, dir = latest.dir, pub_dir = pub_dir,
                sent = display_time(info.created), sent_iso = info.created or "", note = info.note or {},
                base = info.base_revision, current = current and current.number or nil,
                outdated = info.base_revision ~= nil and current ~= nil and info.base_revision < current.number,
                status = status, superseded = complete_count - 1,
              }
              if status == "accepted" then accepted[#accepted + 1] = entry else pending[#pending + 1] = entry end
            end
          end
        end
      end
    end
  end
  local function oldest_first(a, b)
    if a.sent_iso ~= b.sent_iso then return a.sent_iso < b.sent_iso end
    return a.delivery < b.delivery
  end
  table.sort(pending, oldest_first)
  table.sort(accepted, oldest_first)
  table.sort(arriving, function(a, b) return a.delivery < b.delivery end)
  return { pending = pending, accepted = accepted, arriving = arriving }
end

return M
