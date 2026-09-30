local t = require("luatest")
local firstrun = require("bandcollab.firstrun")
local bandfile = require("bandcollab.bandfile")
local localsettings = require("bandcollab.localsettings")
local memfs = require("memfs")

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" }, { id = "drums", label = "Rummut" }, { id = "keys", label = "Koskettimet" } },
  members = {
    { id = "aino", name = "Aino", roles = { "bass" } },
    { id = "eero", name = "Eero", roles = { "drums", "keys" } },
  },
  locations = { master = "m", publications = "p", proposals = "e" },
}

local function band_fs(folder)
  local fs = memfs.new()
  bandfile.write(fs, folder, band)
  return fs
end

t.test("the folder is taken from the file the user picked, on either OS", function()
  t.eq(firstrun.folder_from_file("/home/x/Band/band.json"), "/home/x/Band")
  t.eq(firstrun.folder_from_file("C:\\Users\\Käyttäjä\\Bändi\\band.json"), "C:\\Users\\Käyttäjä\\Bändi")
end)

t.test("a folder with a valid band.json is accepted", function()
  local b = firstrun.check_folder(band_fs("/band"), "/band")
  t.eq(b.name, "Example Band")
end)

t.test("a folder without band.json is rejected, and so is an empty choice", function()
  local _, code = firstrun.check_folder(memfs.new({ ["/other/notes.txt"] = "x" }), "/other")
  t.eq(code, "band_unreadable")
  local _, code2 = firstrun.check_folder(memfs.new(), "")
  t.eq(code2, "band_unreadable")
  local _, code3 = firstrun.check_folder(memfs.new(), nil)
  t.eq(code3, "band_unreadable")
end)

t.test("a broken or too-new band.json is rejected with the matching reason", function()
  local _, c1 = firstrun.check_folder(memfs.new({ ["/b/band.json"] = "{oops" }), "/b")
  t.eq(c1, "band_invalid")
  local _, c2 = firstrun.check_folder(memfs.new({ ["/b/band.json"] = '{"schema":99}' }), "/b")
  t.eq(c2, "band_too_new")
end)

t.test("members are offered with their instruments", function()
  local list = firstrun.member_choices(band)
  t.eq(#list, 2)
  t.eq(list[1].name, "Aino"); t.eq(list[1].roles, "Basso")
  t.eq(list[2].roles, "Rummut, Koskettimet")
end)

t.test("completing stores band folder and member; an unknown member stores nothing", function()
  local s = localsettings.new(localsettings.memory_backend())
  local ok, code = firstrun.complete(s, band, "/band", "nobody")
  t.eq(ok, nil); t.eq(code, "firstrun_unknown_member")
  t.falsy(s:is_configured())
  t.truthy(firstrun.complete(s, band, "/band", "eero"))
  t.eq(s:member(), "eero"); t.eq(s:band_folder(), "/band")
end)

t.test("a stored setup is still valid only while the folder and member exist", function()
  local s = localsettings.new(localsettings.memory_backend())
  local _, need = firstrun.current(s, band_fs("/band"))
  t.eq(need, "firstrun_needed")
  firstrun.complete(s, band, "/band", "aino")
  local b, member = firstrun.current(s, band_fs("/band"))
  t.eq(b.name, "Example Band"); t.eq(member, "aino")
  local _, code = firstrun.current(s, memfs.new())            -- the folder has disappeared
  t.eq(code, "band_unreadable")
  local fs2 = memfs.new()
  local reduced = { schema = 1, name = "X", language = "fi", producer = "eero",
    roles = band.roles, members = { band.members[2] }, locations = band.locations }
  bandfile.write(fs2, "/band", reduced)
  local _, code2 = firstrun.current(s, fs2)                   -- Aino is no longer a member
  t.eq(code2, "firstrun_unknown_member")
end)
