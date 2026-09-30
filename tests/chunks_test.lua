local t = require("luatest")
local chunks = require("bandcollab.chunks")

local one = table.concat({
  "<TRACK {A}", "NAME \"Basso\"", "<ITEM", "POSITION 0", "<SOURCE WAVE", "FILE \"media/a.wav\"", ">", ">", "<FXCHAIN", "<VST \"x\"", "QUJD", ">", ">", ">",
}, "\n")

t.test("a single track with nested blocks is one chunk", function()
  local list = chunks.split(one)
  t.eq(#list, 1)
  t.eq(list[1], one .. "\n")
end)

t.test("several tracks, indented or not, split at the right places", function()
  local indented = one:gsub("\n", "\n  ")
  for _, text in ipairs({ one .. "\n" .. one, indented .. "\n" .. indented, one .. "\n\n" .. one .. "\n" }) do
    local list = chunks.split(text)
    t.eq(#list, 2)
    for _, c in ipairs(list) do t.truthy(c:find("^%s*<TRACK")); t.truthy(c:find(">\n$")) end
  end
end)

t.test("text outside tracks is ignored, an empty text gives no chunks", function()
  t.eq(#chunks.split(""), 0)
  t.eq(#chunks.split("junk\nmore junk\n"), 0)
  t.eq(#chunks.split("header\n" .. one .. "\nfooter\n"), 1)
end)

t.test("a half-written track (no closing) is not returned", function()
  t.eq(#chunks.split("<TRACK {A}\nNAME x\n<ITEM\n"), 0)
end)

t.test("Windows line endings are handled", function()
  local list = chunks.split((one .. "\n" .. one):gsub("\n", "\r\n"))
  t.eq(#list, 2)
end)
