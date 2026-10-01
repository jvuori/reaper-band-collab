local t = require("luatest")
local songs_list = require("bandcollab.songs_list")
local manifest = require("bandcollab.manifest")
local cycles = require("bandcollab.cycles")
local json = require("bandcollab.json")
local memfs = require("memfs")

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" } }, members = { { id = "aino", name = "Aino", roles = { "bass" } } },
  locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" },
  libraries = { { id = "harjoitukset", label = "Harjoitukset", kind = "dated" }, { id = "levytys", label = "Levytys", kind = "flat" } },
}
local PUB = "/band/julkaisut"

-- a finished publication revision of a song
local function revision(fs, song_dir, n, title, extra)
  local dir = song_dir .. "/r" .. n
  fs.files[dir .. "/stems/bass.wav"] = ("s"):rep(500)
  fs.files[dir .. "/publication.json"] = json.encode({ schema = 1, song = { id = "s0123456789abcdef", title = title or "Biisi" }, revision = n })
  for k, v in pairs(extra or {}) do fs.files[dir .. "/" .. k] = v end
  manifest.write(fs, dir, manifest.build(fs, dir, { created = "T" }))
  return dir
end

t.test("a song with a complete publication is offered, with its title and newest revision", function()
  local fs = memfs.new()
  local song = PUB .. "/harjoitukset/2026-09-29/biisi"
  revision(fs, song, 1, "Yö kuka minä"); revision(fs, song, 2, "Yö kuka minä")
  local r = songs_list.list(fs, band, "/band")
  t.eq(#r.songs, 1); t.eq(#r.arriving, 0)
  local s = r.songs[1]
  t.eq(s.title, "Yö kuka minä"); t.eq(s.latest, 2); t.eq(s.cycle, "2026-09-29"); t.eq(s.slug, "biisi")
  t.eq(s.library, "harjoitukset"); t.eq(s.library_label, "Harjoitukset"); t.eq(s.id, "s0123456789abcdef")
  t.falsy(s.closed)
end)

t.test("a song whose only publication is unfinished is not offered, but is reported as arriving", function()
  local fs = memfs.new()
  local song = PUB .. "/harjoitukset/2026-09-29/biisi"
  fs.files[song .. "/r1/stems/bass.wav"] = "half"
  local r = songs_list.list(fs, band, "/band")
  t.eq(#r.songs, 0); t.eq(#r.arriving, 1); t.eq(r.arriving[1].slug, "biisi")
end)

t.test("a publication with a stem that has not fully arrived is not offered", function()
  local fs = memfs.new()
  local song = PUB .. "/harjoitukset/2026-09-29/biisi"
  local dir = revision(fs, song, 1)
  fs.files[dir .. "/stems/bass.wav"] = ("s"):rep(100)
  local r = songs_list.list(fs, band, "/band")
  t.eq(#r.songs, 0); t.eq(#r.arriving, 1)
end)

t.test("when the newest revision is damaged, the newest usable one is offered", function()
  local fs = memfs.new()
  local song = PUB .. "/harjoitukset/2026-09-29/biisi"
  revision(fs, song, 1)
  local dir2 = revision(fs, song, 2)
  fs.files[dir2 .. "/stems/bass.wav"] = "short"
  local r = songs_list.list(fs, band, "/band")
  t.eq(#r.songs, 1); t.eq(r.songs[1].latest, 1)
end)

t.test("nothing published gives two empty lists", function()
  local r = songs_list.list(memfs.new(), band, "/band")
  t.eq(#r.songs, 0); t.eq(#r.arriving, 0)
end)

t.test("songs are found in dated and flat libraries and ordered newest rehearsal first", function()
  local fs = memfs.new()
  revision(fs, PUB .. "/harjoitukset/2026-09-22/vanha", 1, "Vanha")
  revision(fs, PUB .. "/harjoitukset/2026-09-29/uusi", 1, "Uusi")
  revision(fs, PUB .. "/harjoitukset/2026-09-29/aakkonen", 1, "Ääkkönen")
  revision(fs, PUB .. "/levytys/virallinen", 1, "Virallinen")
  fs.files[PUB .. "/harjoitukset/notes/x.txt"] = "not a cycle"
  local r = songs_list.list(fs, band, "/band")
  local order = {}
  for _, s in ipairs(r.songs) do order[#order + 1] = s.title end
  t.eq(table.concat(order, "|"), "Uusi|Ääkkönen|Vanha|Virallinen")
  t.eq(r.songs[4].cycle, nil)
end)

t.test("a song in a closed cycle is listed but marked closed", function()
  local fs = memfs.new()
  revision(fs, PUB .. "/harjoitukset/2026-09-29/biisi", 1)
  cycles.ensure(fs, band, "/band", band.libraries[1], "2026-09-29", "T")
  cycles.close(fs, band, "/band", band.libraries[1], "2026-09-29", "T2")
  local r = songs_list.list(fs, band, "/band")
  t.eq(#r.songs, 1); t.truthy(r.songs[1].closed)
end)
