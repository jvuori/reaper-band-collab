local t = require("luatest")
local template = require("bandcollab.template")
local folders = require("bandcollab.folders")

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" }, { id = "drums", label = "Rummut" }, { id = "keys", label = "Koskettimet" } },
  members = {
    { id = "aino", name = "Aino", roles = { "bass" } },
    { id = "eero", name = "Eero", roles = { "drums", "keys" } },
  },
  locations = { master = "M", publications = "P", proposals = "E" },
}

t.test("one folder per role, in the band's role order, each with at least one track", function()
  local plan = template.plan(band)
  t.eq(#plan, 6)
  local top = folders.top_level(template.depths(plan))
  t.eq(#top, 3)
  t.eq(plan[top[1].first].role, "bass")
  t.eq(plan[top[2].first].role, "drums")
  t.eq(plan[top[3].first].role, "keys")
end)

t.test("track counts are honoured, with a minimum of one", function()
  local plan = template.plan(band, { bass = 3, drums = 0, keys = 2.9 })
  local top = folders.top_level(template.depths(plan))
  t.eq(top[1].last - top[1].first, 3)
  t.eq(top[2].last - top[2].first, 1)
  t.eq(top[3].last - top[3].first, 2)
end)

t.test("folder names show role and owner; children are numbered when there are several", function()
  local plan = template.plan(band, { bass = 2 })
  t.eq(plan[1].name, "Basso - Aino")
  t.eq(plan[2].name, "Basso 1")
  t.eq(plan[3].name, "Basso 2")
  t.eq(plan[4].name, "Rummut - Eero")
  t.eq(plan[5].name, "Rummut")
end)

t.test("only folders carry owner data; a member with two roles owns both folders", function()
  local plan = template.plan(band)
  local owners = {}
  for _, e in ipairs(plan) do
    if e.kind == "folder" then owners[e.role] = e.owner else t.eq(e.owner, nil) end
  end
  t.eq(owners.bass, "aino"); t.eq(owners.drums, "eero"); t.eq(owners.keys, "eero")
end)

t.test("a role nobody owns still gets a folder, without an owner", function()
  local b = { roles = { { id = "x", label = "X" } }, members = {} }
  local plan = template.plan(b)
  t.eq(plan[1].owner, nil)
  t.eq(plan[1].name, "X")
end)

t.test("roles share a colour with their tracks and colours differ between roles", function()
  local plan = template.plan(band)
  t.eq(plan[1].color, plan[2].color)
  t.truthy(plan[1].color ~= plan[3].color)
end)
