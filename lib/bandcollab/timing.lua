-- Timing information of a song (tempo map, length, section markers) and the comparison between
-- two revisions. A change here can move recordings out of line with the band, so it is flagged.
local M = {}

M.TOLERANCE = 0.001 -- seconds; smaller differences are rounding noise

local function near(a, b) return math.abs((a or 0) - (b or 0)) <= M.TOLERANCE end

local function same_list(a, b, eq)
  if #a ~= #b then return false end
  for i = 1, #a do if not eq(a[i], b[i]) then return false end end
  return true
end

local function tempo_eq(x, y)
  return near(x.pos, y.pos) and near(x.bpm, y.bpm) and x.num == y.num and x.den == y.den and (x.linear or false) == (y.linear or false)
end

local function marker_eq(x, y)
  return near(x.pos, y.pos) and near(x.rgnend, y.rgnend) and (x.region or false) == (y.region or false)
end

-- capture(data) -> a timing record from plain values (the REAPER side fills `data`)
--   data.length (seconds), data.bpm, data.beats_per_measure, data.tempo_map, data.markers, data.sample_rate
function M.capture(data)
  return {
    length = data.length,
    bpm = data.bpm,
    beats_per_measure = data.beats_per_measure,
    sample_rate = data.sample_rate,
    tempo_map = data.tempo_map or {},
    markers = data.markers or {},
  }
end

-- compare(previous, current) -> { changed = bool, reasons = { "length", "tempo", "sections" } }
-- With no previous revision there is nothing to compare, so nothing is flagged.
function M.compare(previous, current)
  local reasons = {}
  if previous then
    if not near(previous.length, current.length) then reasons[#reasons + 1] = "length" end
    if not near(previous.bpm, current.bpm) or previous.beats_per_measure ~= current.beats_per_measure
      or not same_list(previous.tempo_map or {}, current.tempo_map or {}, tempo_eq) then
      reasons[#reasons + 1] = "tempo"
    end
    if not same_list(previous.markers or {}, current.markers or {}, marker_eq) then reasons[#reasons + 1] = "sections" end
  end
  return { changed = #reasons > 0, reasons = reasons }
end

return M
