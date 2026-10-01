local t = require("luatest")
local runtime = require("bandcollab.guardian_runtime")
local guardian = require("bandcollab.guardian")
local songfile = require("bandcollab.songfile")
local json = require("bandcollab.json")
local memfs = require("memfs")

local band = {
  schema = 1, name = "X", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" } }, members = { { id = "aino", name = "Aino", roles = { "bass" } }, { id = "eero", name = "Eero", roles = {} } },
  locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" },
}

local function world()
  local fs = memfs.new()
  songfile.write(fs, "/band/tuottaja/x/biisi", { id = "s0123456789abcdef", title = "Biisi", slug = "biisi", library = "x" })
  return fs, runtime.new(fs, band, "/band", "eero", function() return "2026-10-02T21:40:00Z" end)
end

local MASTER = { handle = "H1", file = "/band/tuottaja/x/biisi/biisi.rpp" }
local OTHER = { handle = "H2", file = "/home/eero/demo.rpp" }

t.test("an ordinary project among the open ones causes no alert", function()
  local _, rt = world()
  t.eq(#rt:scan({ OTHER }), 0)
end)

t.test("opening the master as a member gives one strong alert, and it is logged", function()
  local fs, rt = world()
  local alerts = rt:scan({ OTHER, MASTER })
  t.eq(#alerts, 1)
  t.eq(alerts[1].handle, "H1"); t.eq(alerts[1].warnings[1].code, "master"); t.eq(alerts[1].warnings[1].severity, "strong")
  local line = json.decode(fs.files["/band/ehdotukset/eero/guardian.log"]:match("[^\n]+"))
  t.eq(line.code, "master"); t.eq(line.at, "2026-10-02T21:40:00Z"); t.eq(line.file, MASTER.file)
end)

t.test("the same open project is not warned about again while it stays open", function()
  local fs, rt = world()
  t.eq(#rt:scan({ MASTER }), 1)
  for _ = 1, 5 do t.eq(#rt:scan({ MASTER }), 0) end
  local lines = 0
  for _ in fs.files["/band/ehdotukset/eero/guardian.log"]:gmatch("[^\n]+") do lines = lines + 1 end
  t.eq(lines, 1, "one open, one log line")
end)

t.test("closing and reopening the project warns again", function()
  local _, rt = world()
  t.eq(#rt:scan({ MASTER }), 1)
  t.eq(#rt:scan({}), 0)                         -- closed
  t.eq(#rt:scan({ MASTER }), 1)                 -- opened again
end)

t.test("another file opened in the same tab is a new open", function()
  local fs, rt = world()
  fs.files["/home/eero/demo.rpp"] = "<REAPER_PROJECT>"
  t.eq(#rt:scan({ { handle = "H1", file = "/home/eero/demo.rpp" } }), 0)
  t.eq(#rt:scan({ { handle = "H1", file = MASTER.file } }), 1)
end)

t.test("an unsaved tab (no file) is ignored", function()
  local _, rt = world()
  t.eq(#rt:scan({ { handle = "H3", file = nil } }), 0)
end)

t.test("the producer opening the master is not bothered", function()
  local fs = memfs.new()
  songfile.write(fs, "/band/tuottaja/x/biisi", { id = "s0123456789abcdef", title = "Biisi", slug = "biisi", library = "x" })
  local rt = runtime.new(fs, band, "/band", "aino")
  t.eq(#rt:scan({ MASTER }), 0)
  t.falsy(fs.exists("/band/ehdotukset/aino/guardian.log"))
end)
