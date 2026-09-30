local t = require("luatest")
local folders = require("bandcollab.folders")

t.test("a simple folder spans until its closing track", function()
  local d = { 1, 0, -1, 0 }
  t.eq(folders.span(d, 1), 3)
  t.eq(folders.span(d, 2), 2)   -- not a folder start
  t.eq(folders.span(d, 4), 4)
end)

t.test("nested folders close together with -2", function()
  local d = { 1, 1, 0, -2, 0 }
  t.eq(folders.span(d, 1), 4)
  t.eq(folders.span(d, 2), 4)
end)

t.test("a nested folder closing before its parent", function()
  local d = { 1, 1, -1, 0, -1 }
  t.eq(folders.span(d, 2), 3)
  t.eq(folders.span(d, 1), 5)
end)

t.test("an unclosed folder runs to the end", function()
  t.eq(folders.span({ 1, 0, 0 }, 1), 3)
end)

t.test("top_level lists only outermost folders, in order", function()
  local d = { 0, 1, 0, -1, 1, 1, -1, -1, 0 }
  local top = folders.top_level(d)
  t.eq(#top, 2)
  t.eq(top[1].first, 2); t.eq(top[1].last, 4)
  t.eq(top[2].first, 5); t.eq(top[2].last, 8)
end)

t.test("inside and folder_of", function()
  local d = { 0, 1, 0, 0, -1, 0 }
  t.eq(table.concat(folders.inside(d, 2), ","), "3,4,5")
  t.eq(#folders.inside(d, 1), 0)
  t.eq(folders.folder_of(d, 4).first, 2)
  t.eq(folders.folder_of(d, 6), nil)
  t.eq(folders.folder_of(d, 1), nil)
end)

t.test("stray negative depth at top level is ignored", function()
  t.eq(#folders.top_level({ -1, 0 }), 0)
end)
