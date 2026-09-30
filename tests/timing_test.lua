local t = require("luatest")
local timing = require("bandcollab.timing")

local function song(overrides)
  local s = {
    length = 180.0, bpm = 120, beats_per_measure = 4, sample_rate = 48000,
    tempo_map = {},
    markers = { { pos = 0, name = "intro" }, { pos = 16, name = "verse" }, { pos = 48, rgnend = 80, region = true, name = "chorus" } },
  }
  for k, v in pairs(overrides or {}) do s[k] = v end
  return timing.capture(s)
end

t.test("the first revision has nothing to compare with, so nothing is flagged", function()
  local c = timing.compare(nil, song())
  t.falsy(c.changed); t.eq(#c.reasons, 0)
end)

t.test("identical timing is not a change", function()
  t.falsy(timing.compare(song(), song()).changed)
end)

t.test("a lengthened section is flagged as a change of length and sections", function()
  local before = song()
  local after = song({ length = 188.0, markers = { { pos = 0, name = "intro" }, { pos = 16, name = "verse" }, { pos = 48, rgnend = 88, region = true, name = "chorus" } } })
  local c = timing.compare(before, after)
  t.truthy(c.changed)
  t.eq(table.concat(c.reasons, ","), "length,sections")
end)

t.test("a changed tempo or time signature is flagged as tempo", function()
  t.eq(table.concat(timing.compare(song(), song({ bpm = 124 })).reasons, ","), "tempo")
  t.eq(table.concat(timing.compare(song(), song({ beats_per_measure = 3 })).reasons, ","), "tempo")
  local with_map = song({ tempo_map = { { pos = 60, bpm = 130, num = 4, den = 4 } } })
  t.eq(table.concat(timing.compare(song(), with_map).reasons, ","), "tempo")
  t.falsy(timing.compare(with_map, song({ tempo_map = { { pos = 60, bpm = 130, num = 4, den = 4 } } })).changed)
end)

t.test("differences below a millisecond are rounding noise", function()
  t.falsy(timing.compare(song(), song({ length = 180.0004 })).changed)
  t.truthy(timing.compare(song(), song({ length = 180.01 })).changed)
end)

t.test("moving a marker is a change of sections; renaming one is not", function()
  local moved = song({ markers = { { pos = 0 }, { pos = 20 }, { pos = 48, rgnend = 80, region = true } } })
  t.eq(table.concat(timing.compare(song(), moved).reasons, ","), "sections")
  local renamed = song({ markers = { { pos = 0, name = "a" }, { pos = 16, name = "b" }, { pos = 48, rgnend = 80, region = true, name = "c" } } })
  t.falsy(timing.compare(song(), renamed).changed)
end)

t.test("an added marker is a change of sections", function()
  local more = song({ markers = { { pos = 0 }, { pos = 16 }, { pos = 32 }, { pos = 48, rgnend = 80, region = true } } })
  t.eq(table.concat(timing.compare(song(), more).reasons, ","), "sections")
end)
