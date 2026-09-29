local t = require("luatest")
local bandfile = require("bandcollab.bandfile")
local json = require("bandcollab.json")
local memfs = require("memfs")

local function band()
  return {
    schema = 1, name = "Example Band", language = "fi", producer = "aino",
    roles = { { id = "bass", label = "Basso" }, { id = "drums", label = "Rummut" }, { id = "keys", label = "Koskettimet" } },
    members = {
      { id = "aino", name = "Aino", roles = { "bass" } },
      { id = "eero", name = "Eero", roles = { "drums", "keys" } },
    },
    locations = { master = "Tuottaja", publications = "Julkaisut", proposals = "Ehdotukset" },
  }
end

local function invalid(mutate, detail_part)
  local b = band()
  mutate(b)
  local ok, code, detail = bandfile.validate(b)
  t.eq(ok, nil)
  t.eq(code, "band_invalid")
  if detail_part then t.truthy(tostring(detail):find(detail_part, 1, true), "detail was: " .. tostring(detail)) end
end

t.test("a valid band file is accepted", function()
  t.truthy(bandfile.validate(band()))
end)

t.test("write then read round trips through the file system, Finnish text included", function()
  local fs = memfs.new()
  t.truthy(bandfile.write(fs, "/band", band()))
  local read = bandfile.read(fs, "/band")
  t.eq(read.name, "Example Band")
  t.eq(read.members[2].roles[2], "keys")
  t.eq(read.roles[3].label, "Koskettimet")
end)

t.test("a file newer than this tool supports is refused with a clear code", function()
  local b = band(); b.schema = 2
  local fs = memfs.new({ ["/band/band.json"] = json.encode(b) })
  local ok, code, detail = bandfile.read(fs, "/band")
  t.eq(ok, nil)
  t.eq(code, "band_too_new")
  t.eq(detail, 2)
end)

t.test("a missing file and broken JSON are reported differently", function()
  local _, code1 = bandfile.read(memfs.new(), "/band")
  t.eq(code1, "band_unreadable")
  local _, code2 = bandfile.read(memfs.new({ ["/band/band.json"] = "{oops" }), "/band")
  t.eq(code2, "band_invalid")
end)

t.test("invalid contents are rejected with the offending field named", function()
  invalid(function(b) b.name = "" end, "name")
  invalid(function(b) b.schema = "1" end, "schema")
  invalid(function(b) b.language = nil end, "language")
  invalid(function(b) b.roles = {} end, "roles")
  invalid(function(b) b.roles[2].id = "bass" end, "duplicate role")
  invalid(function(b) b.members[2].id = "aino" end, "duplicate member")
  invalid(function(b) b.members[1].roles = {} end, "roles")
  invalid(function(b) b.members[1].roles = { "flute" } end, "unknown role")
  invalid(function(b) b.members[2].roles = { "drums", "keys", "bass" } end, "two owners")
  invalid(function(b) b.producer = "nobody" end, "producer")
  invalid(function(b) b.locations.master = nil end, "locations.master")
  invalid(function(b) b.locations = nil end, "locations")
  local ok, code = bandfile.validate("nope")
  t.eq(ok, nil); t.eq(code, "band_invalid")
end)

t.test("write refuses an invalid band and writes nothing", function()
  local fs = memfs.new()
  local b = band(); b.producer = "nobody"
  local ok, code = bandfile.write(fs, "/band", b)
  t.eq(ok, nil)
  t.eq(code, "band_invalid")
  t.falsy(fs.exists("/band/band.json"))
end)

t.test("one member can own several roles, and owners can be looked up", function()
  local b = band()
  t.eq(bandfile.owner_of(b, "keys").id, "eero")
  t.eq(bandfile.owner_of(b, "flute"), nil)
  local roles = bandfile.roles_of(b, "eero")
  t.eq(#roles, 2)
  t.eq(roles[1].id, "drums")
  t.eq(roles[2].id, "keys")
  t.eq(#bandfile.roles_of(b, "nobody"), 0)
end)
