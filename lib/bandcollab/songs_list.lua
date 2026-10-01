-- Which songs can a member start working on? Those with at least one complete, intact publication.
-- Songs whose publication is still arriving (or damaged) are reported separately, so the panel can
-- say "not published yet" instead of offering something that would fail.
local revisions = require("bandcollab.revisions")
local manifest = require("bandcollab.manifest")
local cycles = require("bandcollab.cycles")
local bandfile = require("bandcollab.bandfile")
local json = require("bandcollab.json")

local M = {}

local function song_folders(fs, dir)
  local out = {}
  for _, e in ipairs(fs.list(dir) or {}) do if e.is_dir then out[#out + 1] = e.name end end
  return out
end

-- newest complete revision whose files are all present (sizes are checked, hashes are not:
-- listing must be quick; the hashes are checked when a workspace is made or updated)
function M.latest_usable(fs, song_dir)
  local best
  for _, r in ipairs(revisions.list(fs, song_dir)) do
    if r.complete and manifest.verify(fs, r.dir, { check_hash = false }) then best = r end
  end
  return best
end

-- list(fs, band, band_folder) -> { songs = {...}, arriving = {...} }
-- song = { library =, library_label =, cycle =, slug =, title =, dir =, latest = number, closed = bool }
function M.list(fs, band, band_folder)
  local songs, arriving = {}, {}
  for _, lib in ipairs(bandfile.libraries(band)) do
    local base = cycles.dir(band, band_folder, "publications", lib.id)
    local places = {}
    if lib.kind == "dated" then
      for _, name in ipairs(song_folders(fs, base)) do
        if cycles.valid_date(name) then places[#places + 1] = { cycle = name, dir = base .. "/" .. name } end
      end
    else
      places[1] = { cycle = nil, dir = base }
    end
    for _, place in ipairs(places) do
      for _, slug in ipairs(song_folders(fs, place.dir)) do
        local song_dir = place.dir .. "/" .. slug
        local all = revisions.list(fs, song_dir)
        if #all > 0 then
          local latest = M.latest_usable(fs, song_dir)
          local entry = { library = lib.id, library_label = lib.label, cycle = place.cycle, slug = slug, dir = song_dir, title = slug }
          if latest then
            local info = json.try_decode(fs.read_all(latest.dir .. "/publication.json") or "")
            if type(info) == "table" and info.song and info.song.title then entry.title = info.song.title; entry.id = info.song.id end
            entry.latest = latest.number
            entry.closed = not cycles.check_open(fs, band, band_folder, lib.id, place.cycle)
            songs[#songs + 1] = entry
          else
            arriving[#arriving + 1] = entry
          end
        end
      end
    end
  end
  local function order(a, b)
    if a.library ~= b.library then return a.library < b.library end
    if (a.cycle or "") ~= (b.cycle or "") then return (a.cycle or "") > (b.cycle or "") end -- newest rehearsal first
    return a.title:lower() < b.title:lower()
  end
  table.sort(songs, order)
  table.sort(arriving, order)
  return { songs = songs, arriving = arriving }
end

return M
