local t = require("luatest")
local deliveries = require("bandcollab.deliveries")
local manifest = require("bandcollab.manifest")
local json = require("bandcollab.json")
local memfs = require("memfs")

local OUT = "/band/ehdotukset/eero/harjoitukset/2026-09-29/biisi/outbox"

local function finish(fs, id, files)
  local dir = OUT .. "/" .. id
  for k, v in pairs(files or { ["own/drums/tracks.chunk"] = "<TRACK\n>" }) do fs.files[dir .. "/" .. k] = v end
  manifest.write(fs, dir, manifest.build(fs, dir, { created = "T" }))
  return dir
end

t.test("delivery ids are UTC timestamps that sort in time order and are safe file names", function()
  local a, b = deliveries.new_id(0), deliveries.new_id(86400)
  t.eq(a, "d19700101T000000Z"); t.eq(b, "d19700102T000000Z")
  t.truthy(a < b)
  t.falsy(a:find("[:/\\ ]"))
end)

t.test("two sends in the same second get different ids", function()
  local fs = memfs.new()
  local id1 = deliveries.unique_id(fs, OUT, 1000)
  fs.files[OUT .. "/" .. id1 .. "/x"] = "x"
  local id2 = deliveries.unique_id(fs, OUT, 1000)
  fs.files[OUT .. "/" .. id2 .. "/x"] = "x"
  local id3 = deliveries.unique_id(fs, OUT, 1000)
  t.eq(id2, id1 .. "-2"); t.eq(id3, id1 .. "-3")
end)

t.test("deliveries are listed oldest first; only real delivery folders count", function()
  local fs = memfs.new()
  finish(fs, "d20260929T210000Z"); finish(fs, "d20260929T200000Z")
  fs.files[OUT .. "/notes/x"] = "x"; fs.files[OUT .. "/dtoday/x"] = "x"
  local list = deliveries.list(fs, OUT)
  t.eq(#list, 2)
  t.eq(list[1].id, "d20260929T200000Z"); t.eq(list[2].id, "d20260929T210000Z")
  t.truthy(list[1].complete)
end)

t.test("a newer delivery supersedes an older one, and the older one is kept", function()
  local fs = memfs.new()
  local first = finish(fs, "d20260929T200000Z", { ["a"] = "first" })
  finish(fs, "d20260929T210000Z", { ["a"] = "second" })
  t.eq(deliveries.latest(fs, OUT).id, "d20260929T210000Z")
  t.eq(fs.files[first .. "/a"], "first")
  t.truthy(manifest.verify(fs, first))
end)

t.test("an unfinished delivery is never the latest", function()
  local fs = memfs.new()
  finish(fs, "d20260929T200000Z")
  fs.files[OUT .. "/d20260929T210000Z/own/x"] = "half"
  t.eq(deliveries.latest(fs, OUT).id, "d20260929T200000Z")
  t.falsy(deliveries.list(fs, OUT)[2].complete)
  t.eq(deliveries.latest(memfs.new(), OUT), nil)
end)

t.test("a delivery is pending until the producer records it as taken in", function()
  local fs = memfs.new()
  local pub = "/band/julkaisut/harjoitukset/2026-09-29/biisi"
  t.eq(deliveries.status(fs, pub, "d20260929T200000Z"), "pending")
  fs.files[pub .. "/imports.json"] = json.encode({ schema = 1, imports = { { delivery = "d20260929T200000Z", member = "eero", at = "T" } } })
  local status, item = deliveries.status(fs, pub, "d20260929T200000Z")
  t.eq(status, "accepted"); t.eq(item.member, "eero")
  t.eq(deliveries.status(fs, pub, "d20260929T210000Z"), "pending")
  fs.files[pub .. "/imports.json"] = "{oops"
  t.eq(deliveries.status(fs, pub, "d20260929T200000Z"), "pending")
end)

t.test("delivery.json is read back, or nil when unusable", function()
  local fs = memfs.new({ ["/d/delivery.json"] = json.encode({ schema = 1, member = "eero", base_revision = 3 }) })
  t.eq(deliveries.read(fs, "/d").base_revision, 3)
  t.eq(deliveries.read(memfs.new(), "/d"), nil)
  t.eq(deliveries.read(memfs.new({ ["/d/delivery.json"] = "{oops" }), "/d"), nil)
end)
