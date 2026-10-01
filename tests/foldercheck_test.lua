local t = require("luatest")
local foldercheck = require("bandcollab.foldercheck")
local registry = require("bandcollab.registry")
local songfile = require("bandcollab.songfile")
local manifest = require("bandcollab.manifest")
local cycles = require("bandcollab.cycles")
local deliveries = require("bandcollab.deliveries")
local strings = require("bandcollab.strings")
local json = require("bandcollab.json")
local memfs = require("memfs")

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" } },
  members = { { id = "aino", name = "Aino", roles = { "bass" } }, { id = "eero", name = "Eero", roles = {} } },
  locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" },
  libraries = { { id = "harjoitukset", label = "Harjoitukset", kind = "dated" }, { id = "levytys", label = "Levytys", kind = "flat" } },
}
local B = "/band"
local MASTER = B .. "/tuottaja/harjoitukset/2026-09-29/biisi"
local PUB = B .. "/julkaisut/harjoitukset/2026-09-29/biisi"
local SONG = B .. "/ehdotukset/eero/harjoitukset/2026-09-29/biisi"
local ID = "s0123456789abcdef"

local function finish(fs, dir)
  assert(manifest.write(fs, dir, manifest.build(fs, dir, { created = "T" })))
end

-- a healthy band folder: a registered song with its media, a publication, and an imported delivery
local function healthy()
  local fs = memfs.new()
  songfile.write(fs, MASTER, { id = ID, title = "Biisi", slug = "biisi", library = "harjoitukset", cycle = "2026-09-29" })
  fs.files[MASTER .. "/biisi.rpp"] = '<REAPER_PROJECT\n  <ITEM\n    <SOURCE WAVE\n      FILE "media/a.wav"\n    >\n  >\n>\n'
  fs.files[MASTER .. "/media/a.wav"] = "audio"
  local reg = registry.empty()
  registry.put(reg, { id = ID, title = "Biisi", slug = "biisi", library = "harjoitukset", cycle = "2026-09-29", path = "tuottaja/harjoitukset/2026-09-29/biisi" })
  registry.save(fs, registry.file(band, B), reg)
  cycles.ensure(fs, band, B, band.libraries[1], "2026-09-29", "T")
  fs.files[PUB .. "/r1/stems/bass.wav"] = "stem"
  finish(fs, PUB .. "/r1")
  fs.files[SONG .. "/outbox/d20260929T200000Z/own/x/tracks.chunk"] = "<TRACK\n>"
  finish(fs, SONG .. "/outbox/d20260929T200000Z")
  deliveries.record_import(fs, PUB, { delivery = "d20260929T200000Z", member = "eero", at = "T" })
  fs.files[SONG .. "/work/biisi.rpp"] = "<REAPER_PROJECT\n>\n"
  fs.files[SONG .. "/work/workspace.json"] = "{}"
  return fs
end

local function codes(problems)
  local out = {}
  for _, p in ipairs(problems) do out[#out + 1] = p.code end
  return table.concat(out, ",")
end

local function find(problems, code)
  for _, p in ipairs(problems) do if p.code == code then return p end end
end

local function snapshot(fs) local o = {}; for k, v in pairs(fs.files) do o[k] = v end; return o end
local function same(a, b) for k, v in pairs(a) do if b[k] ~= v then return false end end; for k in pairs(b) do if a[k] == nil then return false end end; return true end

t.test("a healthy band folder has nothing to report, and checking changes nothing", function()
  local fs = healthy()
  local before = snapshot(fs)
  t.eq(codes(foldercheck.check(fs, band, B)), "")
  t.truthy(same(before, fs.files), "the check must only look")
end)

t.test("an unfinished publication and an unfinished delivery are reported", function()
  local fs = healthy()
  fs.files[PUB .. "/r2/stems/bass.wav"] = "half"
  fs.files[SONG .. "/outbox/d20260930T100000Z/own/x/tracks.chunk"] = "half"
  local p = foldercheck.check(fs, band, B)
  t.eq(codes(p), "incomplete_pack,incomplete_pack")
  t.eq(p[1].path, "ehdotukset/eero/harjoitukset/2026-09-29/biisi/outbox/d20260930T100000Z")
  t.eq(p[2].path, "julkaisut/harjoitukset/2026-09-29/biisi/r2")
end)

t.test("a project in the master area that is not a registered song is reported", function()
  local fs = healthy()
  fs.files[B .. "/tuottaja/harjoitukset/2026-09-29/outo/outo.rpp"] = "<REAPER_PROJECT>"
  local p = foldercheck.check(fs, band, B)
  t.eq(codes(p), "unregistered_project")
  t.eq(p[1].path, "tuottaja/harjoitukset/2026-09-29/outo/outo.rpp")
end)

t.test("two songs with the same id are both named", function()
  local fs = healthy()
  songfile.write(fs, B .. "/tuottaja/levytys/kopio", { id = ID, title = "Kopio", slug = "kopio", library = "levytys" })
  fs.files[B .. "/tuottaja/levytys/kopio/kopio.rpp"] = "<REAPER_PROJECT>"
  local p = foldercheck.check(fs, band, B)
  t.truthy(find(p, "duplicate_song_id"))
  t.truthy(find(p, "unregistered_project"), "the copy is also not registered at its place")
  local dup = find(p, "duplicate_song_id")
  t.truthy(dup.detail:find("biisi") or dup.path:find("biisi"), "the other song is named")
end)

t.test("a registered song whose folder has gone is reported", function()
  local fs = healthy()
  for path in pairs(fs.files) do if path:sub(1, #MASTER + 1) == MASTER .. "/" then fs.files[path] = nil end end
  t.eq(codes(foldercheck.check(fs, band, B)), "registered_missing")
end)

t.test("things in the wrong area are reported", function()
  local fs = healthy()
  fs.files[PUB .. "/viaan.rpp"] = "<REAPER_PROJECT>"
  fs.files[MASTER .. "/r5/stems/x.wav"] = "stem"; finish(fs, MASTER .. "/r5")
  fs.files[MASTER .. "/d20260930T100000Z/own/x"] = "x"; finish(fs, MASTER .. "/d20260930T100000Z")
  local list = {}
  for _, p in ipairs(foldercheck.check(fs, band, B)) do if p.code == "wrong_area" then list[#list + 1] = p.detail end end
  table.sort(list)
  t.eq(#list, 3)
  t.truthy(list[1]:find("project file") or list[2]:find("project file") or list[3]:find("project file"))
end)

t.test("a stems folder named like a revision in a member's workspace is not a mistake", function()
  local fs = healthy()
  fs.files[SONG .. "/work/stems/r1/bass.wav"] = "stem"
  finish(fs, SONG .. "/work/stems/r1")
  t.eq(codes(foldercheck.check(fs, band, B)), "")
end)

t.test("a proposal waiting in a closed cycle is reported; an imported one is not", function()
  local fs = healthy()
  fs.files[SONG .. "/outbox/d20260930T100000Z/own/x/tracks.chunk"] = "<TRACK\n>"
  finish(fs, SONG .. "/outbox/d20260930T100000Z")
  t.eq(codes(foldercheck.check(fs, band, B)), "", "an open cycle is fine")
  cycles.close(fs, band, B, band.libraries[1], "2026-09-29", "T2")
  t.eq(codes(foldercheck.check(fs, band, B)), "proposal_in_closed_cycle")
  deliveries.record_import(fs, PUB, { delivery = "d20260930T100000Z", member = "eero", at = "T" })
  t.eq(codes(foldercheck.check(fs, band, B)), "")
end)

t.test("audio the project does not use is reported (for example left over from an undone import)", function()
  local fs = healthy()
  fs.files[MASTER .. "/media/d1/drums/old.wav"] = "left over"
  local p = foldercheck.check(fs, band, B)
  t.eq(codes(p), "unreferenced_media")
  t.eq(p[1].path, "tuottaja/harjoitukset/2026-09-29/biisi/media/d1/drums/old.wav")
end)

t.test("names that do not follow the rules are reported at each level", function()
  local fs = healthy()
  fs.files[B .. "/tuottaja/harjoitukset/2026-09-29/Uusi kansio/x.txt"] = "x"
  fs.files[B .. "/tuottaja/harjoitukset/tänään/x.txt"] = "x"
  fs.files[B .. "/julkaisut/nope/x.txt"] = "x"
  fs.files[B .. "/ehdotukset/joku/x.txt"] = "x"
  local bad = {}
  for _, p in ipairs(foldercheck.check(fs, band, B)) do if p.code == "bad_name" then bad[p.path] = p.detail end end
  t.truthy(bad["tuottaja/harjoitukset/2026-09-29/Uusi kansio"]:find("safe folder name"))
  t.truthy(bad["tuottaja/harjoitukset/tänään"]:find("date"))
  t.truthy(bad["julkaisut/nope"]:find("libraries"))
  t.truthy(bad["ehdotukset/joku"]:find("member"))
end)

t.test("leftovers are reported with a delete fix, which only runs when asked and only deletes that file", function()
  local fs = healthy()
  fs.files[MASTER .. "/media/a.wav.reapeaks"] = "peaks"
  fs.files[MASTER .. "/biisi.rpp-bak"] = "backup"
  fs.files[B .. "/tuottaja/registry.json.tmp"] = "{}"
  local p = foldercheck.check(fs, band, B)
  t.eq(codes(p), "stray_file,stray_file,stray_file")
  for _, problem in ipairs(p) do t.eq(problem.fix, "delete"); t.eq(problem.severity, "tidy") end
  local real, tidy = foldercheck.split(p)
  t.eq(#real, 0); t.eq(#tidy, 3)
  t.truthy(fs.exists(MASTER .. "/biisi.rpp-bak"), "reporting must not delete anything")

  t.truthy(foldercheck.fix(fs, B, p[1]))
  local remaining = 0
  for _, path in ipairs({ MASTER .. "/media/a.wav.reapeaks", MASTER .. "/biisi.rpp-bak", B .. "/tuottaja/registry.json.tmp" }) do if fs.exists(path) then remaining = remaining + 1 end end
  t.eq(remaining, 2, "only the chosen file went")
  t.truthy(fs.exists(MASTER .. "/media/a.wav"), "real audio is never touched")
  t.eq(#foldercheck.check(fs, band, B), 2)
end)

t.test("a problem without a safe fix has none, and asking to fix it does nothing", function()
  local fs = healthy()
  fs.files[PUB .. "/r2/stems/bass.wav"] = "half"
  local problem = foldercheck.check(fs, band, B)[1]
  t.eq(problem.fix, nil)
  local ok = foldercheck.fix(fs, B, problem)
  t.eq(ok, nil)
  t.truthy(fs.exists(PUB .. "/r2/stems/bass.wav"))
end)

t.test("every finding has a plain description in both languages", function()
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")
  local EN = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  for _, code in ipairs({ "incomplete_pack", "unregistered_project", "duplicate_song_id", "registered_missing", "wrong_area",
    "proposal_in_closed_cycle", "unreferenced_media", "bad_name", "stray_file" }) do
    local d = foldercheck.describe(S, { code = code, path = "x/y", detail = "z" })
    t.truthy(d.what:find("x/y", 1, true) and #d.action > 5, code)
    t.truthy(EN:has("check." .. code .. ".what", "en") and EN:has("check." .. code .. ".action", "fi"), code)
  end
end)

t.test("the tool's own backups are not songs, and audio a backup still uses is not unreferenced", function()
  local fs = healthy()
  fs.files[MASTER .. "/backups/i19700124T033320Z/biisi.rpp"] = '<REAPER_PROJECT\n  <ITEM\n    <SOURCE WAVE\n      FILE "media/old.wav"\n    >\n  >\n>\n'
  fs.files[MASTER .. "/backups/i19700124T033320Z/import.json"] = "{}"
  fs.files[MASTER .. "/media/old.wav"] = "the take an undo returns to"
  fs.files[MASTER .. "/Backups/biisi-2026.rpp-bak"] = "reaper autosave"
  local real, tidy = foldercheck.split(foldercheck.check(fs, band, B))
  t.eq(#real, 0, "no false alarms: " .. codes(real))
  t.eq(#tidy, 1)
  fs.files[MASTER .. "/media/forgotten.wav"] = "nothing uses this"
  t.eq(codes((foldercheck.split(foldercheck.check(fs, band, B)))), "unreferenced_media")
end)
