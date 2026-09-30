local t = require("luatest")
local publish_session = require("bandcollab.publish_session")
local songfile = require("bandcollab.songfile")
local manifest = require("bandcollab.manifest")
local strings = require("bandcollab.strings")
local memfs = require("memfs")

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" }, { id = "drums", label = "Rummut" } },
  members = { { id = "aino", name = "Aino", roles = { "bass" } }, { id = "eero", name = "Eero", roles = { "drums" } } },
  locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" },
  libraries = { { id = "harjoitukset", label = "Harjoitukset", kind = "dated" }, { id = "levytys", label = "Levytys", kind = "flat" } },
}
local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")

-- a fake REAPER: one open project, saved or not, and a publisher that records what it was asked
local function world(opts)
  opts = opts or {}
  local fs = memfs.new()
  local song_dir = "/band/tuottaja/harjoitukset/2026-09-29/biisi"
  if opts.registered ~= false then
    songfile.write(fs, song_dir, { id = "s0123456789abcdef", title = "Biisi", slug = "biisi", library = "harjoitukset", cycle = "2026-09-29" })
  end
  local env = { calls = {}, is_dirty = opts.dirty or false, open = opts.open ~= false }
  env.project = function() return env.open and "PROJ" or nil end
  env.file = function(proj) return proj and (song_dir .. "/biisi.rpp") or nil end
  env.dirty = function() return env.is_dirty end
  env.publish = function(_, _, _, _, _, o)
    env.calls[#env.calls + 1] = o
    o.step("stem: bass"); o.yield(); o.step("reference")
    if opts.fail then return nil, opts.fail, "levy täynnä" end
    return { revision = 1, structure = { changed = false, reasons = {} } }
  end
  local sess = assert(publish_session.new(fs, band, "/band", S, "aino", env))
  return sess, env, fs
end

local function drive(s) local n = 0; while not s:step() do n = n + 1; assert(n < 1000) end; return n end

t.test("only the producer can publish", function()
  local sess, code = publish_session.new(memfs.new(), band, "/band", S, "eero", {})
  t.eq(sess, nil); t.eq(code, "not_producer")
end)

t.test("the status says what the open project is", function()
  local s1 = world({ registered = false })
  t.eq(s1:refresh().kind, "no_song")
  local s2 = world({ open = false })
  t.eq(s2:refresh().kind, "no_song")
  local s3 = world({ dirty = true })
  t.eq(s3:refresh().kind, "unsaved")
  local s4 = world()
  local st = s4:refresh()
  t.eq(st.kind, "ready"); t.eq(st.song.title, "Biisi"); t.eq(st.next, 1); t.eq(st.last, nil)
end)

t.test("the next revision number follows what is already published", function()
  local s, _, fs = world()
  local pub = "/band/julkaisut/harjoitukset/2026-09-29/biisi"
  for _, n in ipairs({ 1, 2 }) do
    fs.files[pub .. "/r" .. n .. "/a.wav"] = "x"
    manifest.write(fs, pub .. "/r" .. n, manifest.build(fs, pub .. "/r" .. n, { created = "T" }))
  end
  local st = s:refresh()
  t.eq(st.last, 2); t.eq(st.next, 3)
  fs.files[pub .. "/r3/half.wav"] = "x"  -- an unfinished leftover is reused, not skipped
  t.eq(s:refresh().next, 3)
end)

t.test("publishing runs in slices, passes the note and requests, and reports the revision", function()
  local s, env = world()
  s.note.summary = "  Uusi miksaus  "
  s.note.body = "Basso ylös."
  s:add_task("Rummut", "uusi otto kertosäkeeseen")
  s:add_task("Basso", "   ")            -- an empty request is dropped
  t.truthy(s:start())
  t.truthy(s:running())
  t.falsy(s:step(), "not finished after the first slice")
  drive(s)
  t.falsy(s:running())
  t.truthy(s.result.ok); t.eq(s.result.revision, 1)
  t.truthy(s.result.text:find("r1"))
  local call = env.calls[1]
  t.eq(call.note.summary, "Uusi miksaus"); t.eq(call.note.body, "Basso ylös.")
  t.eq(#call.tasks, 1); t.eq(call.tasks[1].who, "Rummut")
  t.eq(s.note.summary, "", "the form is cleared after a successful publish"); t.eq(#s.tasks, 0)
end)

t.test("progress text is available while running", function()
  local s = world()
  s:start()
  s:step()
  t.eq(s.progress, "stem: bass")
end)

t.test("a failure is reported in plain words and the form is kept", function()
  local s = world({ fail = "render_failed" })
  s.note.summary = "Yritys"
  s:start(); drive(s)
  t.falsy(s.result.ok)
  t.truthy(s.result.text:find("levy täynnä", 1, true))
  t.eq(s.note.summary, "Yritys")
end)

t.test("starting is refused when the project cannot be published", function()
  local unsaved = world({ dirty = true })
  local ok, code = unsaved:start()
  t.eq(ok, nil); t.eq(code, "project_unsaved")
  local unknown = world({ registered = false })
  local ok2, code2 = unknown:start()
  t.eq(ok2, nil); t.eq(code2, "not_a_song")
end)
