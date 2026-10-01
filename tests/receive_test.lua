local t = require("luatest")
local receive = require("bandcollab.receive")
local registry = require("bandcollab.registry")
local songfile = require("bandcollab.songfile")
local manifest = require("bandcollab.manifest")
local cycles = require("bandcollab.cycles")
local ids = require("bandcollab.ids")
local memfs = require("memfs")

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" } },
  members = { { id = "aino", name = "Aino", roles = { "bass" } } },
  locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" },
  libraries = { { id = "harjoitukset", label = "Harjoitukset", kind = "dated" }, { id = "levytys", label = "Levytys", kind = "flat" } },
}

local function wav(n)
  local body = "WAVE" .. "fmt " .. string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, 48000, 96000, 2, 16) .. "data" .. string.pack("<I4", n) .. ("\1"):rep(n)
  return "RIFF" .. string.pack("<I4", #body) .. body
end

-- puts a song (project file plus one recording) into fs under `dir`
local function stage(fs, dir, name, media_size)
  fs.files[dir .. "/" .. name .. ".rpp"] = "<REAPER_PROJECT 0.1 \"7.0\" 0\n  <ITEM\n    <SOURCE WAVE\n      FILE \"media/" .. name .. ".wav\"\n    >\n  >\n>\n"
  fs.files[dir .. "/media/" .. name .. ".wav"] = wav(media_size or 400)
end

local function world()
  local fs = memfs.new()
  local ctx = assert(receive.context(fs, band, "/band"))
  return fs, ctx
end

local function by_name(list) local m = {}; for _, c in ipairs(list) do m[c.name] = c end; return m end

local NOW = "2026-09-29T20:00:00Z"

t.test("first arrival: a project without identity is registered silently, with id, song.json, manifest and registry entry", function()
  local fs, ctx = world()
  stage(fs, "/stage/ilta", "eka")
  local c = receive.candidates(ctx, "/stage")[1]
  t.eq(c.identity.state, "new")
  t.truthy(c.selected)
  local entry = receive.import(ctx, c, { library = "harjoitukset", cycle = "2026-09-29", now = NOW })
  t.truthy(entry)
  t.truthy(ids.valid(entry.id))
  t.eq(entry.path, "tuottaja/harjoitukset/2026-09-29/eka")
  t.eq(entry.cycle, "2026-09-29")

  local dest = "/band/" .. entry.path
  t.truthy(fs.exists(dest .. "/eka.rpp"))
  t.truthy(fs.exists(dest .. "/media/eka.wav"))
  t.eq(songfile.read(fs, dest).id, entry.id)
  t.truthy(manifest.verify(fs, dest))

  local reloaded = registry.load(fs, "/band/tuottaja/registry.json")
  t.eq(registry.get(reloaded, entry.id).title, "eka")
  t.falsy(fs.exists("/band/tuottaja/registry.json.tmp"), "temporary registry file left behind")
end)

t.test("the staging folder is left untouched", function()
  local fs, ctx = world()
  stage(fs, "/stage/ilta", "eka")
  local before = fs.files["/stage/ilta/eka.rpp"]
  receive.import(ctx, receive.candidates(ctx, "/stage")[1], { library = "harjoitukset", cycle = "2026-09-29", now = NOW })
  t.eq(fs.files["/stage/ilta/eka.rpp"], before)
  t.truthy(fs.exists("/stage/ilta/media/eka.wav"))
  t.falsy(fs.exists("/stage/ilta/song.json"))
end)

t.test("a moved project registers without any question and keeps its id", function()
  local fs, ctx = world()
  stage(fs, "/stage/a", "biisi")
  local first = receive.import(ctx, receive.candidates(ctx, "/stage")[1], { library = "harjoitukset", cycle = "2026-09-29", now = NOW })

  -- the folder is moved (old place disappears) and shows up somewhere else
  local moved = {}
  for path, data in pairs(fs.files) do
    if path:sub(1, #("/band/" .. first.path)) == "/band/" .. first.path then moved[#moved + 1] = { path, data } end
  end
  local old_dir = "/band/" .. first.path
  for _, m in ipairs(moved) do fs.files[m[1]] = nil; fs.files["/elsewhere/uusi" .. m[1]:sub(#old_dir + 1)] = m[2] end

  local c = receive.candidates(ctx, "/elsewhere")[1]
  t.eq(c.identity.state, "moved")
  t.eq(c.identity.id, first.id)
  t.truthy(c.selected, "a move must not need a decision")
  local entry = receive.import(ctx, c, { library = "levytys", now = NOW })
  t.truthy(entry)
  t.eq(entry.id, first.id)
  t.eq(entry.path, "tuottaja/levytys/biisi")   -- the title was kept, so the folder name follows it
  t.eq(entry.title, "biisi")
  local count = 0; for _ in pairs(ctx.registry.songs) do count = count + 1 end
  t.eq(count, 1)
end)

t.test("a project with an unregistered id keeps that id", function()
  local fs, ctx = world()
  stage(fs, "/stage/x", "outsider")
  songfile.write(fs, "/stage/x", { id = "s00000000deadbeef", title = "Outsider" })
  local entry = receive.import(ctx, receive.candidates(ctx, "/stage")[1], { library = "levytys", now = NOW })
  t.eq(entry.id, "s00000000deadbeef")
end)

t.test("a copy of a registered song (original still there) is flagged and needs a decision", function()
  local fs, ctx = world()
  stage(fs, "/stage/a", "biisi")
  local orig = receive.import(ctx, receive.candidates(ctx, "/stage")[1], { library = "harjoitukset", cycle = "2026-09-29", now = NOW })

  -- someone copies the rehearsal folder into another place (the original stays)
  local old_dir = "/band/" .. orig.path
  local to_copy = {}
  for path, data in pairs(fs.files) do
    if path:sub(1, #old_dir + 1) == old_dir .. "/" then to_copy[#to_copy + 1] = { path, data } end
  end
  for _, f in ipairs(to_copy) do fs.files["/copyhere/biisi-kopio" .. f[1]:sub(#old_dir + 1)] = f[2] end -- (never add keys while iterating)
  local c = receive.candidates(ctx, "/copyhere")[1]
  t.eq(c.identity.state, "copy")
  t.eq(c.identity.entry.id, orig.id)
  t.falsy(c.selected, "a copy must not be pre-selected")

  local nothing, code, detail = receive.import(ctx, c, { library = "levytys", now = NOW })
  t.eq(nothing, nil); t.eq(code, "copy_undecided"); t.eq(detail, "biisi")
  t.eq(registry.get(ctx.registry, orig.id).path, orig.path)

  local entry = receive.import(ctx, c, { library = "levytys", copy = true, now = NOW })
  t.truthy(entry)
  t.truthy(entry.id ~= orig.id)
  t.eq(entry.origin.id, orig.id)
  t.eq(entry.origin.path, orig.path)
  t.eq(songfile.read(fs, "/band/" .. entry.path).id, entry.id)
  t.eq(registry.get(ctx.registry, orig.id).path, orig.path)
  t.eq(#registry.list(ctx.registry), 2)
  t.eq(songfile.read(fs, old_dir).id, orig.id)
end)

t.test("pointing at a folder that is already registered is 'same' and refused", function()
  local fs, ctx = world()
  stage(fs, "/stage/a", "biisi")
  local orig = receive.import(ctx, receive.candidates(ctx, "/stage")[1], { library = "harjoitukset", cycle = "2026-09-29", now = NOW })
  local c = receive.candidates(ctx, "/band/tuottaja/harjoitukset")[1]
  t.eq(c.identity.state, "same")
  local nothing, code = receive.import(ctx, c, { library = "levytys", now = NOW })
  t.eq(nothing, nil); t.eq(code, "already_registered")
end)

t.test("receiving the same staging folder twice does not register duplicates", function()
  local fs, ctx = world()
  stage(fs, "/stage/a", "biisi")
  local first = receive.import(ctx, receive.candidates(ctx, "/stage")[1], { library = "harjoitukset", cycle = "2026-09-29", now = NOW })
  local c = receive.candidates(ctx, "/stage")[1]
  t.eq(c.identity.state, "already_received")
  t.falsy(c.selected)
  local nothing, code, detail = receive.import(ctx, c, { library = "harjoitukset", cycle = "2026-09-29", now = NOW })
  t.eq(nothing, nil); t.eq(code, "already_received"); t.eq(detail, "biisi")
  t.eq(#registry.list(ctx.registry), 1)
  -- after the project changes it is a different project again
  fs.files["/stage/a/biisi.rpp"] = fs.files["/stage/a/biisi.rpp"] .. "\n; edited\n"
  t.eq(receive.candidates(ctx, "/stage")[1].identity.state, "new")
end)

t.test("an incomplete song is refused and nothing is written", function()
  local fs, ctx = world()
  stage(fs, "/stage/a", "biisi", 4000)
  fs.files["/stage/a/media/biisi.wav"] = fs.files["/stage/a/media/biisi.wav"]:sub(1, 1500)
  local c = receive.candidates(ctx, "/stage")[1]
  t.falsy(c.selected)
  local nothing, code, problems = receive.import(ctx, c, { library = "harjoitukset", cycle = "2026-09-29", now = NOW })
  t.eq(nothing, nil); t.eq(code, "incomplete")
  t.eq(problems[1].code, "truncated_file")
  t.falsy(fs.exists("/band/tuottaja/registry.json"))
  for path in pairs(fs.files) do t.falsy(path:find("^/band/"), "wrote " .. path) end
end)

t.test("a failed copy leaves no registry entry behind", function()
  local fs, ctx = world()
  stage(fs, "/stage/a", "biisi")
  local c = receive.candidates(ctx, "/stage")[1]
  local real = fs.open_write
  fs.open_write = function(p) if p:find("biisi.wav", 1, true) then return nil, "disk full" end return real(p) end
  local nothing, code, detail = receive.import(ctx, c, { library = "harjoitukset", cycle = "2026-09-29", now = NOW })
  t.eq(nothing, nil); t.eq(code, "cannot_copy"); t.truthy(tostring(detail):find("disk full"))
  t.eq(#registry.list(ctx.registry), 0)
  t.falsy(fs.exists("/band/tuottaja/registry.json"))
end)

t.test("several songs of one rehearsal are grouped under its date, in both areas", function()
  local fs, ctx = world()
  stage(fs, "/stage/ilta/a", "eka"); stage(fs, "/stage/ilta/b", "toka"); stage(fs, "/stage/c", "kolmas")
  local list = receive.candidates(ctx, "/stage")
  t.eq(#list, 3)
  for _, c in ipairs(list) do
    t.truthy(c.selected)
    t.truthy(receive.import(ctx, c, { library = "harjoitukset", cycle = "2026-09-29", now = NOW }))
  end
  local names = {}
  for _, e in ipairs(fs.list("/band/tuottaja/harjoitukset/2026-09-29")) do names[#names + 1] = e.name end
  t.eq(table.concat(names, ","), "cycle.json,eka,kolmas,toka")
  t.truthy(fs.exists("/band/julkaisut/harjoitukset/2026-09-29/cycle.json"))
  for _, e in ipairs(registry.list(ctx.registry)) do t.eq(e.cycle, "2026-09-29") end
  local c = cycles.list(fs, band, "/band", band.libraries[1])
  t.eq(#c, 1); t.eq(c[1].cycle, "2026-09-29"); t.eq(c[1].state, "open")
end)

t.test("a different date makes a separate cycle", function()
  local fs, ctx = world()
  stage(fs, "/stage/a", "eka"); stage(fs, "/stage/b", "toka")
  local list = receive.candidates(ctx, "/stage")
  receive.import(ctx, list[1], { library = "harjoitukset", cycle = "2026-09-22", now = NOW })
  receive.import(ctx, list[2], { library = "harjoitukset", cycle = "2026-09-29", now = NOW })
  local c = cycles.list(fs, band, "/band", band.libraries[1])
  t.eq(#c, 2); t.eq(c[1].cycle, "2026-09-22"); t.eq(c[2].cycle, "2026-09-29")
end)

t.test("a flat library puts songs directly under the library, without a cycle", function()
  local fs, ctx = world()
  stage(fs, "/stage/a", "eka")
  local e = receive.import(ctx, receive.candidates(ctx, "/stage")[1], { library = "levytys", cycle = "2026-09-29", now = NOW })
  t.eq(e.path, "tuottaja/levytys/eka")
  t.eq(e.cycle, nil)
  t.eq(#cycles.list(fs, band, "/band", band.libraries[2]), 0)
end)

t.test("songs with the same title get distinct folders, case-insensitively", function()
  local fs, ctx = world()
  stage(fs, "/stage/a", "Kappale"); stage(fs, "/stage/b", "KAPPALE"); stage(fs, "/stage/c", "kappale")
  local slugs = {}
  for _, c in ipairs(receive.candidates(ctx, "/stage")) do
    slugs[#slugs + 1] = receive.import(ctx, c, { library = "levytys", now = NOW, title = c.name }).slug
  end
  table.sort(slugs)
  t.eq(table.concat(slugs, ","), "kappale,kappale-2,kappale-3")
end)

t.test("special characters in a title give a safe folder and keep the display title", function()
  local fs, ctx = world()
  stage(fs, "/stage/a", "x")
  local e = receive.import(ctx, receive.candidates(ctx, "/stage")[1], { library = "levytys", title = "Yö: kuka? Minä", now = NOW })
  t.eq(e.slug, "yo-kuka-mina")
  t.eq(e.title, "Yö: kuka? Minä")
  t.eq(songfile.read(fs, "/band/" .. e.path).title, "Yö: kuka? Minä")
end)

t.test("bad dates and unknown libraries are refused before anything is written", function()
  local fs, ctx = world()
  stage(fs, "/stage/a", "x")
  local c = receive.candidates(ctx, "/stage")[1]
  local _, code1 = receive.import(ctx, c, { library = "harjoitukset", cycle = "2026-13-40" })
  t.eq(code1, "bad_date")
  local _, code2 = receive.import(ctx, c, { library = "nope" })
  t.eq(code2, "unknown_library")
  for path in pairs(fs.files) do t.falsy(path:find("^/band/"), "wrote " .. path) end
end)

t.test("a damaged registry is reported, not silently replaced", function()
  local fs = memfs.new({ ["/band/tuottaja/registry.json"] = "{oops" })
  local ctx, code = receive.context(fs, band, "/band")
  t.eq(ctx, nil); t.eq(code, "registry_invalid")
end)

t.test("song ids are unique even when the random source repeats itself", function()
  local values = { 1, 1, 1, 1, 2, 2 }
  local i = 0
  local rng = function() i = i + 1; return values[i] or 9 end
  local taken = { [ids.generate({}, function() return 1 end)] = true }
  local id = ids.generate(taken, rng)
  t.falsy(taken[id])
  t.truthy(ids.valid(id))
end)

t.test("the master gets a distinctive file name when asked, and everything else keeps working", function()
  local fs, ctx = world()
  stage(fs, "/stage/a", "eka")
  local c = receive.candidates(ctx, "/stage")[1]
  local e = receive.import(ctx, c, { library = "harjoitukset", cycle = "2026-09-29", now = NOW, master_prefix = "PAAVERSIO" })
  t.truthy(e)
  local dest = "/band/" .. e.path
  t.truthy(fs.exists(dest .. "/PAAVERSIO_eka.rpp"), "the master must carry a name that says what it is")
  t.falsy(fs.exists(dest .. "/eka.rpp"))
  t.truthy(fs.exists(dest .. "/media/eka.wav")); t.eq(songfile.read(fs, dest).id, e.id)
  t.truthy(manifest.verify(fs, dest), "the manifest must describe the renamed file, so the folder verifies")
end)
