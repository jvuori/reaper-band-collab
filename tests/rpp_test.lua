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

t.test("rewrite_media replaces only the mapped FILE paths and keeps everything else", function()
  local text = '<TRACK\n  <ITEM\n    <SOURCE WAVE\n      FILE "media/a b.wav" 1\n    >\n  >\n  <ITEM\n    <SOURCE WAVE\n      FILE "/other/c.wav"\n    >\n  >\n  NAME "FILE not this"\n>\n'
  local out = rpp.rewrite_media(text, { ["media/a b.wav"] = "media/a-b.wav" })
  t.truthy(out:find('FILE "media/a-b.wav" 1', 1, true))
  t.truthy(out:find('FILE "/other/c.wav"', 1, true))
  t.truthy(out:find('NAME "FILE not this"', 1, true))
  t.eq(out:gsub('media/a%-b%.wav', 'media/a b.wav'), text)
end)

t.test("rewrite_media keeps the quoting style and the trailing newline (or lack of it)", function()
  t.eq(rpp.rewrite_media("FILE `x\"y.wav`\n", { ['x"y.wav'] = "media/z.wav" }), "FILE `media/z.wav`\n")
  t.eq(rpp.rewrite_media("  FILE bare.wav", { ["bare.wav"] = "media/n.wav" }), '  FILE "media/n.wav"')
  t.eq(rpp.rewrite_media("a\nb", {}), "a\nb")
  t.eq(rpp.rewrite_media("a\nb\n", {}), "a\nb\n")
end)

t.test("title is read from the project-level TITLE line only", function()
  t.eq(rpp.title('<REAPER_PROJECT 0.1 "7.0" 0\n  TITLE "Yö: kuka minä"\n  <TRACK\n    NAME "x"\n  >\n>\n'), "Yö: kuka minä")
  t.eq(rpp.title('<REAPER_PROJECT\n  <TRACK\n      TITLE "not this one"\n  >\n>\n'), nil)
  t.eq(rpp.title("<REAPER_PROJECT\n  LOOP 0\n>\n"), nil)
  t.eq(rpp.title('<REAPER_PROJECT\n  TITLE ""\n>\n'), nil)
  t.eq(rpp.title('<REAPER_PROJECT\n  TITLE `has "quotes"`\n>\n'), 'has "quotes"')
end)
