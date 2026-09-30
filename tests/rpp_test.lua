local t = require("luatest")
local rpp = require("bandcollab.rpp")

t.test("media references are read from FILE lines, in order, without duplicates", function()
  local text = [[
<REAPER_PROJECT 0.1 "7.0" 0
  RENDER_FILE "/tmp/render"
  <TRACK
    <ITEM
      <SOURCE WAVE
        FILE "media/take1.wav"
      >
    >
    <ITEM
      <SOURCE WAVE
        FILE "media/take2.wav" 1
      >
    >
    <ITEM
      <SOURCE WAVE
        FILE "media/take1.wav"
      >
    >
  >
>
]]
  local refs = rpp.media_refs(text)
  t.eq(table.concat(refs, "|"), "media/take1.wav|media/take2.wav")
end)

t.test("quoting styles, Windows paths, CRLF and Finnish names", function()
  local text = 'FILE "C:\\Audio\\Yö äiti.wav"\r\n    FILE `has "quotes".wav`\r\n  FILE \'single.wav\'\r\nFILE bare.wav\r\n'
  local refs = rpp.media_refs(text)
  t.eq(refs[1], "C:\\Audio\\Yö äiti.wav")
  t.eq(refs[2], 'has "quotes".wav')
  t.eq(refs[3], "single.wav")
  t.eq(refs[4], "bare.wav")
end)

t.test("only real FILE lines count, not other settings that mention files", function()
  local refs = rpp.media_refs('RENDER_FILE "x.wav"\nLOOPSTART 0\n  PROFILE_FILE "y"\n')
  t.eq(#refs, 0)
end)

t.test("absolute paths are recognized on both systems", function()
  t.truthy(rpp.is_absolute("/home/x/a.wav"))
  t.truthy(rpp.is_absolute("C:\\Audio\\a.wav"))
  t.truthy(rpp.is_absolute("D:/Audio/a.wav"))
  t.truthy(rpp.is_absolute("\\\\server\\share\\a.wav"))
  t.falsy(rpp.is_absolute("media/a.wav"))
  t.falsy(rpp.is_absolute("a.wav"))
end)
