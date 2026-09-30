-- Libraries hold songs; a "dated" library (rehearsals) groups them into cycles, one per date.
-- A closed cycle accepts no new proposals but stays available for listening.
-- The state is written to the producer's area and mirrored to the publications area, which is
-- where members can see it.
local json = require("bandcollab.json")
local bandfile = require("bandcollab.bandfile")

local M = {}

M.FILENAME = "cycle.json"

-- valid_date(text) -> true for a real calendar date written YYYY-MM-DD
function M.valid_date(text)
  local y, m, d = tostring(text):match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if not y then return false end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m < 1 or m > 12 or d < 1 then return false end
  local days = { 31, (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  return d <= days[m]
end

-- dir(band, band_folder, area, library_id [, cycle]) -> folder of a library or of one cycle in it
--   area: "master" or "publications"
function M.dir(band, band_folder, area, library_id, cycle)
  local d = band_folder .. "/" .. band.locations[area] .. "/" .. library_id
  if cycle then d = d .. "/" .. cycle end
  return d
end

-- song_dir(band, band_folder, library, cycle, slug) -> where a received song lives in the master area
function M.song_dir(band, band_folder, library, cycle, slug)
  return M.dir(band, band_folder, "master", library.id, library.kind == "dated" and cycle or nil) .. "/" .. slug
end

local function write_state(fs, dir, state, now)
  local ok = fs.mkdirs(dir)
  if not ok then return nil, "cannot create " .. dir end
  local data = { schema = 1, state = state.state, opened = state.opened, closed = state.closed }
  return fs.write_all(dir .. "/" .. M.FILENAME, json.encode(data, { pretty = true }) .. "\n")
end

local function read_state(fs, dir)
  local text = fs.read_all(dir .. "/" .. M.FILENAME)
  if not text then return nil end
  local data = json.try_decode(text)
  if type(data) ~= "table" or (data.state ~= "open" and data.state ~= "closed") then return nil end
  return data
end

-- ensure(fs, band, band_folder, library, cycle [, now]) -> state | nil, err
-- Creates the cycle (open) in both areas if it does not exist yet; never reopens a closed one.
function M.ensure(fs, band, band_folder, library, cycle, now)
  if library.kind ~= "dated" then return { state = "open" } end
  if not M.valid_date(cycle) then return nil, "bad_date", cycle end
  local existing = M.state(fs, band, band_folder, library, cycle)
  if existing then return existing end
  local state = { state = "open", opened = now or os.date("!%Y-%m-%dT%H:%M:%SZ") }
  for _, area in ipairs({ "master", "publications" }) do
    local ok, err = write_state(fs, M.dir(band, band_folder, area, library.id, cycle), state)
    if not ok then return nil, err end
  end
  return state
end

-- state(fs, band, band_folder, library, cycle) -> state table | nil (unknown cycle)
-- Members' view first (publications), then the producer's own record.
function M.state(fs, band, band_folder, library, cycle)
  return read_state(fs, M.dir(band, band_folder, "publications", library.id, cycle))
    or read_state(fs, M.dir(band, band_folder, "master", library.id, cycle))
end

-- close(fs, band, band_folder, library, cycle [, now]) -> true | nil, err
function M.close(fs, band, band_folder, library, cycle, now)
  if library.kind ~= "dated" then return nil, "cycle_unknown" end
  if not M.valid_date(cycle) then return nil, "bad_date", cycle end
  local current = M.state(fs, band, band_folder, library, cycle)
  if not current then return nil, "cycle_unknown" end
  local state = { state = "closed", opened = current.opened, closed = now or os.date("!%Y-%m-%dT%H:%M:%SZ") }
  for _, area in ipairs({ "master", "publications" }) do
    local ok, err = write_state(fs, M.dir(band, band_folder, area, library.id, cycle), state)
    if not ok then return nil, err end
  end
  return true
end

-- check_open(fs, band, band_folder, library_id, cycle) -> true | nil, "cycle_closed", cycle
-- The gate every proposal passes. Songs in flat libraries, and cycles nobody has closed, are open.
function M.check_open(fs, band, band_folder, library_id, cycle)
  local library = bandfile.library(band, library_id)
  if not library or library.kind ~= "dated" or not cycle then return true end
  local st = M.state(fs, band, band_folder, library, cycle)
  if st and st.state == "closed" then return nil, "cycle_closed", cycle end
  return true
end

-- list(fs, band, band_folder, library) -> list of { cycle =, state = "open" | "closed" }, oldest first
function M.list(fs, band, band_folder, library)
  local out = {}
  for _, e in ipairs(fs.list(M.dir(band, band_folder, "master", library.id)) or {}) do
    if e.is_dir and M.valid_date(e.name) then
      local st = M.state(fs, band, band_folder, library, e.name)
      out[#out + 1] = { cycle = e.name, state = st and st.state or "open" }
    end
  end
  table.sort(out, function(a, b) return a.cycle < b.cycle end)
  return out
end

return M
