local t = require("luatest")
local import_session = require("bandcollab.import_session")
local strings = require("bandcollab.strings")
local memfs = require("memfs")

local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")
local band = { producer = "aino", members = {}, roles = {}, locations = {} }

local ENTRY = { member = "eero", member_name = "Eero", title = "Yö kuka minä", slug = "biisi", sent = "2026-09-29 20:41",
  song_id = "s1", delivery = "d1", dir = "/d", pub_dir = "/pub", note = { summary = "Tiukennettu säkeistö 2" }, base = 5, current = 8, outdated = true }

local function world(overrides)
  local env = { calls = {}, undo_id = nil }
  env.inbox = function() return { pending = { ENTRY }, accepted = {}, arriving = { { member = "aino", member_name = "Aino", delivery = "d9" } } } end
  env.master = function() return env.master_value end
  env.master_value = { song = { id = "s1" }, file = "/m.rpp", dir = "/m" }
  env.can_undo = function() return env.undo_id end
  env.preview = function(_, _, _, _, entry)
    env.calls[#env.calls + 1] = "preview"
    return env.preview_value or {
      note = entry.note, base = 5, current = 8,
      folders = { { role = "drums", label = "Rummut", before = { tracks = 2, items = 1 }, after = { tracks = 3, items = 4 } },
                  { role = "bass", label = "Basso", ignored = true } },
      warnings = { { code = "import_outdated", severity = "warning", vars = { base = 5, current = 8 } }, { code = "import_conflict", severity = "warning", detail = "Rummut" } },
      timing = { master = { bpm = 120, length = 188 }, proposal = { bpm = 124, length = 196 }, tempo_differs = true },
    }
  end
  env.import = function(_, _, _, _, _, _, o)
    env.calls[#env.calls + 1] = "import"; env.import_opts = o
    o.yield(1, "/m/media/d1/drums/take.wav")
    return env.import_value or { delivery = "d1", backup = "i1", replaced = { { role = "drums", label = "Rummut", tracks = 3 } } }
  end
  env.undo = function() env.calls[#env.calls + 1] = "undo"; if not env.undo_id then return nil, "nothing_to_undo_import" end; env.undo_id = nil; return { delivery = "d1" } end
  env.publications_dir = function() return "/pub" end
  for k, v in pairs(overrides or {}) do env[k] = v end
  local s = assert(import_session.new(memfs.new(), band, "/band", S, "aino", env))
  s:refresh()
  return s, env
end

local function drive(s) local n = 0; while not s:step() do n = n + 1; assert(n < 100) end end

t.test("only the producer sees the proposals", function()
  local s, code = import_session.new(memfs.new(), band, "/band", S, "eero", {})
  t.eq(s, nil); t.eq(code, "not_producer")
end)

t.test("the inbox rows say who, which song and when, and flag an older version", function()
  local s = world()
  t.eq(#s.inbox.pending, 1)
  t.eq(s:row_text(ENTRY), "Eero: Yö kuka minä   (2026-09-29 20:41)")
  t.eq(s:tag(ENTRY), "vanhempi versio r5")
  t.eq(s:tag({ outdated = false }), nil)
  t.eq(#s.inbox.arriving, 1)
end)

t.test("reviewing shows what will be replaced, the versions, timing and warnings, and writes nothing", function()
  local s, env = world()
  t.truthy(s:review(ENTRY))
  local lines = s:lines()
  t.eq(lines[1], "Rummut: korvataan (2 raitaa, 1 klippiä -> 3 raitaa, 4 klippiä)")
  t.eq(lines[2], "Basso: jätetään huomiotta")
  t.eq(lines[3], "Perustuu versioon r5; pääversio on r8.")
  t.truthy(lines[4]:find("120.0")); t.truthy(lines[4]:find("124.0"))
  t.truthy(lines[5]:find("3:08")); t.truthy(lines[5]:find("3:16"))
  local warnings = s:warnings()
  t.eq(#warnings, 2)
  t.truthy(warnings[1].text:find("versiosta r5, ja pääversio on nyt r8", 1, true)); t.truthy(warnings[2].text:find("Rummut"))
  t.eq(s.note.summary, "Tiukennettu säkeistö 2")
  for _, call in ipairs(env.calls) do t.truthy(call == "preview", "only the preview may run: " .. call) end
end)

t.test("cancelling leaves nothing selected and nothing done", function()
  local s, env = world()
  s:review(ENTRY)
  s:cancel()
  t.eq(s.selected, nil); t.eq(s.preview, nil); t.falsy(s:start_import())
  t.eq(#env.calls, 1)
end)

t.test("without the matching master open, the panel says to open it", function()
  local s, env = world()
  env.master_value = nil; s:refresh()
  t.falsy(s:review(ENTRY))
  t.truthy(s.problem.text:find("Avaa ensin"))
  env.master_value = { song = { id = "another" } }; s:refresh()
  t.falsy(s:review(ENTRY)); t.eq(s.problem.code, "open_master")
  t.falsy(s:start_import())
end)

t.test("a proposal that cannot be previewed is explained in plain words", function()
  local s, env = world()
  env.preview = function() return nil, "size_mismatch", "own/drums/tracks.chunk" end
  t.falsy(s:review(ENTRY))
  t.truthy(s.problem.text:find("own/drums/tracks.chunk", 1, true))
end)

t.test("taking it in sends the (possibly edited) note, runs in slices, and clears the review", function()
  local s, env = world()
  s:review(ENTRY)
  s.note.summary = "Rummut tiukennettu säkeistössä 2"; s.note.body = "Muokattu."
  t.truthy(s:start_import())
  t.truthy(s:running()); t.falsy(s:step())
  t.truthy(s.progress:find("take.wav"))
  drive(s)
  t.truthy(s.result.ok); t.truthy(s.result.text:find("Otettu pääversioon"))
  t.eq(env.import_opts.note.summary, "Rummut tiukennettu säkeistössä 2"); t.eq(env.import_opts.note.body, "Muokattu.")
  t.eq(s.selected, nil)
end)

t.test("a failed import is reported in plain words", function()
  local s, env = world()
  env.import = function() return nil, "import_backup_failed", "/m/backups" end
  s:review(ENTRY); s:start_import(); drive(s)
  t.falsy(s.result.ok); t.truthy(s.result.text:find("varmuuskopiota")); t.truthy(s.result.text:find("/m/backups", 1, true))
end)

t.test("the last import can be undone, once", function()
  local s, env = world()
  env.undo_id = "d1"; s:refresh()
  t.eq(s.undo_delivery, "d1")
  t.truthy(s:undo()); t.truthy(s.result.text:find("peruttu"))
  t.eq(s.undo_delivery, nil)
  t.falsy(s:undo()); t.eq(s.result.code, "nothing_to_undo_import")
end)
