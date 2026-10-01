local t = require("luatest")
local picker = require("bandcollab.workspace_picker")
local manifest = require("bandcollab.manifest")
local cycles = require("bandcollab.cycles")
local json = require("bandcollab.json")
local strings = require("bandcollab.strings")
local wm = require("bandcollab.workspace_model")
local memfs = require("memfs")

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" }, { id = "drums", label = "Rummut" }, { id = "keys", label = "Koskettimet" } },
  members = { { id = "aino", name = "Aino", roles = { "bass" } }, { id = "eero", name = "Eero", roles = { "drums", "keys" } } },
  locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" },
  libraries = { { id = "harjoitukset", label = "Harjoitukset", kind = "dated" }, { id = "levytys", label = "Levytys", kind = "flat" } },
}
local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")

local function publish(fs, song_dir, title)
  local dir = song_dir .. "/r1"
  fs.files[dir .. "/stems/bass.wav"] = ("s"):rep(300)
  fs.files[dir .. "/publication.json"] = json.encode({ schema = 1, song = { id = "s0123456789abcdef", title = title } })
  manifest.write(fs, dir, manifest.build(fs, dir, { created = "T" }))
end

local function world()
  local fs = memfs.new()
  local env = { created = {}, opened = {} }
  env.create = function(_, _, _, member, song, o)
    o.yield(1, "/x/work/stems/r1/bass.wav")
    env.created[#env.created + 1] = { member = member, song = song.slug, reference = o.reference_name }
    return { file = "/ws.rpp" }
  end
  env.open = function(file) env.opened[#env.opened + 1] = file end
  return fs, env, picker.new(fs, band, "/band", S, "eero", env)
end

t.test("with nothing published the panel says the producer has not published anything", function()
  local _, _, p = world()
  p:refresh()
  t.eq(#p.songs, 0)
  t.truthy(p:empty_message():find("ei ole vielä julkaissut"))
end)

t.test("a publication that is still arriving is said to be arriving, not offered", function()
  local fs, _, p = world()
  fs.files["/band/julkaisut/harjoitukset/2026-09-29/biisi/r1/stems/bass.wav"] = "half"
  p:refresh()
  t.eq(#p.songs, 0); t.eq(#p.arriving, 1)
  t.truthy(p:empty_message():find("vielä tulossa"))
end)

t.test("published songs are offered, and each shows whether the member already has a workspace", function()
  local fs, _, p = world()
  publish(fs, "/band/julkaisut/harjoitukset/2026-09-29/uusi", "Uusi")
  publish(fs, "/band/julkaisut/harjoitukset/2026-09-22/vanha", "Vanha")
  wm.write_state(fs, "/band/ehdotukset/eero/harjoitukset/2026-09-22/vanha", { song = { id = "s1" }, member = "eero", base_revision = 1, own_fingerprint = "x" })
  t.eq(p:refresh(), 2)
  t.eq(p:empty_message(), nil)
  local by = {}
  for _, s in ipairs(p.songs) do by[s.slug] = s end
  t.eq(by.uusi.workspace, nil); t.truthy(p:can_create(by.uusi))
  t.eq(by.vanha.workspace, "/band/ehdotukset/eero/harjoitukset/2026-09-22/vanha/work/vanha.rpp")
  t.falsy(p:can_create(by.vanha), "one workspace per song")
end)

t.test("a song in a closed cycle can be seen but no workspace can be created", function()
  local fs, _, p = world()
  publish(fs, "/band/julkaisut/harjoitukset/2026-09-29/biisi", "Biisi")
  cycles.ensure(fs, band, "/band", band.libraries[1], "2026-09-29", "T")
  cycles.close(fs, band, "/band", band.libraries[1], "2026-09-29", "T2")
  p:refresh()
  t.truthy(p.songs[1].closed); t.falsy(p:can_create(p.songs[1]))
end)

t.test("creating runs in slices, is done for this member, and refreshes the list", function()
  local fs, env, p = world()
  publish(fs, "/band/julkaisut/harjoitukset/2026-09-29/biisi", "Biisi")
  p:refresh()
  p:start_create(p.songs[1])
  t.truthy(p:running()); t.falsy(p:step())
  t.truthy(p.progress:find("bass.wav"))
  local n = 0; while not p:step() do n = n + 1; assert(n < 100) end
  t.truthy(p.result.ok); t.truthy(p.result.text:find("valmis"))
  t.eq(env.created[1].member, "eero"); t.eq(env.created[1].song, "biisi")
  t.truthy(env.created[1].reference:find("Referenssimiksaus"))
end)

t.test("a refusal is shown in plain words", function()
  local fs, env, p = world()
  publish(fs, "/band/julkaisut/harjoitukset/2026-09-29/biisi", "Biisi")
  env.create = function() return nil, "workspace_exists", "/x" end
  p:refresh(); p:start_create(p.songs[1])
  local n = 0; while not p:step() do n = n + 1; assert(n < 100) end
  t.falsy(p.result.ok); t.truthy(p.result.text:find("jo oma työtila"))
end)

t.test("opening an existing workspace opens its file, and a song without one opens nothing", function()
  local fs, env, p = world()
  publish(fs, "/band/julkaisut/harjoitukset/2026-09-29/biisi", "Biisi")
  wm.write_state(fs, "/band/ehdotukset/eero/harjoitukset/2026-09-29/biisi", { song = { id = "s1" }, member = "eero", base_revision = 1, own_fingerprint = "x" })
  p:refresh(); p:open(p.songs[1])
  t.eq(env.opened[1], "/band/ehdotukset/eero/harjoitukset/2026-09-29/biisi/work/biisi.rpp")
  local _, env2, p2 = world()
  publish(memfs.new(), "/x", "x")
  p2:open({ workspace = nil })
  t.eq(#env2.opened, 0)
end)

t.test("the panel tells the member who they are", function()
  local _, _, p = world()
  t.eq(p:who(), "Sinä olet Eero (Rummut, Koskettimet).")
end)
