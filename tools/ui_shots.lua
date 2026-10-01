-- Draws each UI screen for a while so that tools/ui_shots.sh can capture the window.
-- It doubles as a smoke test: every frame is drawn under pcall, and errors are recorded.
-- Env: BANDCOLLAB_ROOT (repository root), SHOT_DIR (working directory for signal files).
-- Signal files: ready_<name> (contains the window title) -> the shell captures -> ack_<name>.
-- Quits REAPER without ever waiting for a person: an open project with unsaved changes would make
-- the normal quit action ask "save changes?" in a modal dialog, so in that case exit directly.
local function safe_quit()
  local i = 0
  while true do
    local p = reaper.EnumProjects(i, "")
    if not p then break end
    if reaper.IsProjectDirty(p) ~= 0 then os.exit(0, true) end
    i = i + 1
  end
  reaper.Main_OnCommand(40004, 0)
end

local root = assert(os.getenv("BANDCOLLAB_ROOT"), "BANDCOLLAB_ROOT not set")
local dir = assert(os.getenv("SHOT_DIR"), "SHOT_DIR not set")
package.path = table.concat({ root .. "/lib/?.lua", root .. "/ui/?.lua", package.path }, ";")

local strings = require("bandcollab.strings")
local wizard = require("bandcollab.wizard")
local firstrun = require("bandcollab.firstrun")
local messages = require("bandcollab.messages")
local wizard_view = require("wizard_view")
local receive_view = require("receive_view")
local publish_view = require("publish_view")
local sync_view = require("sync_view")
local picker_view = require("picker_view")
local import_view = require("import_view")
local import_session = require("bandcollab.import_session")
local sync_session = require("bandcollab.sync_session")
local workspace_picker = require("bandcollab.workspace_picker")
local wm = require("bandcollab.workspace_model")
local publish_session = require("bandcollab.publish_session")
local songfile = require("bandcollab.songfile")
local manifest = require("bandcollab.manifest")
local json = require("bandcollab.json")
local receive_session = require("bandcollab.receive_session")
package.path = root .. "/tests/?.lua;" .. package.path
local memfs = require("memfs")
local firstrun_view = require("firstrun_view")

local function S(lang) return strings.load(root .. "/strings", { "en", "fi" }, loadfile, lang) end

local function three_members(lang)
  local s = wizard.new(lang)
  s.name = "Example Band"
  local a = wizard.add_member(s, "Aino"); s.members[a].instruments[1] = { label = "Basso", tracks = 2 }
  local e = wizard.add_member(s, "Eero"); s.members[e].instruments[1] = { label = "Rummut", tracks = 4 }
  wizard.add_instrument(s, e, "Koskettimet", 1)
  local p = wizard.add_member(s, "Pia"); s.members[p].instruments[1] = { label = "Laulu", tracks = 1 }
  return s
end

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" }, { id = "drums", label = "Rummut" }, { id = "keys", label = "Koskettimet" } },
  members = { { id = "aino", name = "Aino", roles = { "bass" } }, { id = "eero", name = "Eero", roles = { "drums", "keys" } } },
  locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" },
}

local scenarios = {}
local function scenario(name, lang, width, height, make)
  scenarios[#scenarios + 1] = { name = name, lang = lang, w = width, h = height, make = make }
end

scenario("wizard_empty_fi", "fi", 640, 330, function(s)
  local st = wizard.new("fi"); wizard.add_member(st, "")
  local ui = { folder = "" }
  return function(ctx) return wizard_view.draw(ctx, st, s, ui) end, s:t("ui.wizard.title")
end)
scenario("wizard_three_fi", "fi", 640, 560, function(s)
  local st = three_members("fi")
  local ui = { folder = "/home/user/Band" }
  return function(ctx) return wizard_view.draw(ctx, st, s, ui) end, s:t("ui.wizard.title")
end)
scenario("wizard_problems_fi", "fi", 640, 330, function(s)
  local st = wizard.new("fi"); wizard.add_member(st, "")
  local ui = { folder = "", show_problems = true }
  return function(ctx) return wizard_view.draw(ctx, st, s, ui) end, s:t("ui.wizard.title")
end)
scenario("wizard_done_en", "en", 640, 560, function(s)
  local st = three_members("en")
  local ui = { folder = "/home/user/Band", done = true }
  return function(ctx) return wizard_view.draw(ctx, st, s, ui) end, s:t("ui.wizard.title")
end)
scenario("firstrun_start_fi", "fi", 520, 200, function(s)
  local ui = {}
  return function(ctx) return firstrun_view.draw(ctx, s, ui) end, s:t("ui.firstrun.title")
end)
scenario("firstrun_members_fi", "fi", 520, 330, function(s)
  local ui = { folder = "C:\\Users\\Käyttäjä\\Bändi", choices = firstrun.member_choices(band), selected = "eero" }
  return function(ctx) return firstrun_view.draw(ctx, s, ui) end, s:t("ui.firstrun.title")
end)
scenario("firstrun_error_fi", "fi", 520, 260, function(s)
  local ui = { error = messages.get(s, "band_unreadable") }
  return function(ctx) return firstrun_view.draw(ctx, s, ui) end, s:t("ui.firstrun.title")
end)
scenario("firstrun_done_fi", "fi", 520, 360, function(s)
  local ui = { folder = "C:\\Users\\Käyttäjä\\Bändi", choices = firstrun.member_choices(band), selected = "eero", done_name = "Eero" }
  return function(ctx) return firstrun_view.draw(ctx, s, ui) end, s:t("ui.firstrun.title")
end)

local function wav(n)
  local body = "WAVE" .. "fmt " .. string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, 48000, 96000, 2, 16) .. "data" .. string.pack("<I4", n) .. ("\1"):rep(n)
  return "RIFF" .. string.pack("<I4", #body) .. body
end
local function stage(fs, d, name, size)
  fs.files[d .. "/" .. name .. ".rpp"] = "<REAPER_PROJECT 0.1 \"7.0\" 0\n  <ITEM\n    <SOURCE WAVE\n      FILE \"media/" .. name .. ".wav\"\n    >\n  >\n>\n"
  fs.files[d .. "/media/" .. name .. ".wav"] = wav(size or 300)
end
local function receive_band(lang)
  local b = {}
  for k, v in pairs(band) do b[k] = v end
  b.language = lang
  b.libraries = { { id = "harjoitukset", label = lang == "fi" and "Harjoitukset" or "Rehearsals", kind = "dated" },
                  { id = "levytys", label = lang == "fi" and "Levytys" or "Official", kind = "flat" } }
  return b
end
local function drive(sess) local n = 0; while not sess:step() and n < 10000 do n = n + 1 end end

local function receive_session_ready(lang)
  local s = S(lang)
  local fs = memfs.new()
  stage(fs, "/stage/ilta/a", "Ensimmäinen", 500); stage(fs, "/stage/ilta/b", "Toinen biisi", 4000); stage(fs, "/stage/c", "Kolmas", 500)
  fs.files["/stage/ilta/b/media/Toinen biisi.wav"] = fs.files["/stage/ilta/b/media/Toinen biisi.wav"]:sub(1, 900)
  local b = receive_band(lang)
  local sess = receive_session.new(fs, b, "/band", s, "aino")
  sess:scan("/stage")
  sess.library, sess.cycle = "harjoitukset", "2026-09-29"
  return sess, s, fs
end

scenario("receive_ready_fi", "fi", 760, 330, function(s)
  local sess = receive_session_ready("fi")
  local ui = { staging = "/home/user/rehearsal-copy", scanned = true }
  return function(ctx) return receive_view.draw(ctx, sess, ui) end, s:t("ui.receive.title")
end)
scenario("receive_done_fi", "fi", 760, 470, function(s)
  local sess = receive_session_ready("fi")
  sess:start(); drive(sess)
  local ui = { staging = "/home/user/rehearsal-copy", scanned = true }
  sess:refresh("/stage")
  return function(ctx) return receive_view.draw(ctx, sess, ui) end, s:t("ui.receive.title")
end)
scenario("receive_copy_en", "en", 760, 330, function(s)
  local sess, _, fs = receive_session_ready("en")
  sess:start(); drive(sess)
  local first = sess.results[1].entry
  local to_copy = {}
  for path, data in pairs(fs.files) do
    if path:sub(1, #("/band/" .. first.path) + 1) == "/band/" .. first.path .. "/" then to_copy[#to_copy + 1] = { path, data } end
  end
  for _, f in ipairs(to_copy) do fs.files["/copyhere/x" .. f[1]:sub(#("/band/" .. first.path) + 1)] = f[2] end
  sess:scan("/copyhere")
  local ui = { staging = "/copyhere", scanned = true }
  return function(ctx) return receive_view.draw(ctx, sess, ui) end, s:t("ui.receive.title")
end)

-- publish panel: a fake REAPER environment (one open project, saved or not, a publisher that succeeds)
local function publish_world(lang, opts)
  opts = opts or {}
  local s = S(lang)
  local fs = memfs.new()
  local dir = "/band/tuottaja/harjoitukset/2026-09-29/biisi"
  songfile.write(fs, dir, { id = "s0123456789abcdef", title = lang == "fi" and "Yö kuka minä" or "Night song", slug = "biisi", library = "harjoitukset", cycle = "2026-09-29" })
  local pub = "/band/julkaisut/harjoitukset/2026-09-29/biisi"
  for _, n in ipairs({ 1, 2 }) do
    fs.files[pub .. "/r" .. n .. "/a.wav"] = "x"
    manifest.write(fs, pub .. "/r" .. n, manifest.build(fs, pub .. "/r" .. n, { created = "T" }))
  end
  local env = { project = function() return "PROJ" end, file = function() return dir .. "/biisi.rpp" end, dirty = function() return opts.dirty end }
  env.publish = function(_, _, _, _, _, o)
    o.step("stem: bass")
    return { revision = 3, structure = { changed = true, reasons = { "length" } } }
  end
  local b = receive_band(lang)
  local sess = publish_session.new(fs, b, "/band", s, "aino", env)
  sess:refresh()
  return sess, s
end

scenario("publish_ready_fi", "fi", 680, 520, function(_)
  local sess, s = publish_world("fi")
  sess.note.summary = "Uusi miksaus, basso nostettu"
  sess.note.body = "Kertosäe pidennettiin neljällä tahdilla."
  sess:add_task("Rummut", "uusi otto kertosäkeeseen")
  return function(ctx) return publish_view.draw(ctx, sess, s) end, s:t("ui.publish.title")
end)
scenario("publish_done_en", "en", 680, 400, function(_)
  local sess, s = publish_world("en")
  sess:start(); local n = 0; while not sess:step() and n < 100 do n = n + 1 end
  return function(ctx) return publish_view.draw(ctx, sess, s) end, s:t("ui.publish.title")
end)
scenario("publish_unsaved_fi", "fi", 680, 160, function(_)
  local sess, s = publish_world("fi", { dirty = true })
  return function(ctx) return publish_view.draw(ctx, sess, s) end, s:t("ui.publish.title")
end)

-- Synkronoi panel: fake operations with a canned state
local function sync_world(lang, kind, opts)
  opts = opts or {}
  local s = S(lang)
  local env = { undo_from = opts.undo_from }
  env.status = function()
    return { sync = { kind = kind, master_newer = kind == "down" or kind == "both", own_changed = kind == "up" or kind == "both" },
      arriving = opts.arriving or false, closed = opts.closed or false, proposal = opts.proposal, latest = 4, base = 3 }
  end
  env.can_undo = function() return env.undo_from end
  env.preflight = function() return opts.pre or { problems = {}, blocking = false, warnings = {} } end
  env.fetch = function() return nil end
  local ws = { proj = "P", dir = "/d", file = "/d/work/x.rpp", state = { member = "eero", base_revision = 3, song = { title = lang == "fi" and "Yö kuka minä" or "Night song" } } }
  local sess = sync_session.new(memfs.new(), receive_band(lang), "/band", s, ws, env)
  sess:refresh()
  return sess, s
end
local function sync_scenario(name, lang, kind, height, opts, prepare)
  scenario(name, lang, 640, height, function(_)
    local sess, s = sync_world(lang, kind, opts)
    if prepare then prepare(sess) end
    return function(ctx) return sync_view.draw(ctx, sess) end, s:t("ui.sync.title")
  end)
end
sync_scenario("sync_none_fi", "fi", "none", 130, nil)
sync_scenario("sync_down_fi", "fi", "down", 190, nil)
sync_scenario("sync_up_fi", "fi", "up", 330, { proposal = { id = "d1", sent = "2026-09-29 21:40", status = "pending" } }, function(sess)
  sess.note.summary = "Tiukennettu säkeistö 2"
  sess.note.body = "Uudet täytteet kohdassa 1:32."
end)
sync_scenario("sync_both_en", "en", "both", 470, nil)
sync_scenario("sync_problems_fi", "fi", "up", 480, {
  pre = { blocking = true, warnings = { "send_empty" }, problems = {
    { code = "send_orphans", severity = "blocking", detail = 2, fix = "move_orphans" },
    { code = "send_empty", severity = "warning" },
  } },
}, function(sess) sess:check() end)
sync_scenario("sync_fetched_fi", "fi", "up", 380, { undo_from = 3 }, function(sess)
  sess.result = { ok = true, text = sess.S:t("ui.sync.fetched", { n = 4 }),
    warning = sess.S:t("ui.sync.structure_warning", { reasons = "pituus, osiot" }) }
end)

-- workspace picker
local function picker_world(lang, with_songs)
  local s = S(lang)
  local fs = memfs.new()
  local b = receive_band(lang)
  b.members = { { id = "aino", name = "Aino", roles = { "bass" } }, { id = "eero", name = "Eero", roles = { "drums", "keys" } } }
  b.roles = { { id = "bass", label = "Basso" }, { id = "drums", label = "Rummut" }, { id = "keys", label = "Koskettimet" } }
  if with_songs then
    local function pub(dir, title)
      local d = dir .. "/r1"
      fs.files[d .. "/stems/bass.wav"] = ("s"):rep(300)
      fs.files[d .. "/publication.json"] = json.encode({ schema = 1, song = { id = "s0123456789abcdef", title = title } })
      manifest.write(fs, d, manifest.build(fs, d, { created = "T" }))
    end
    pub("/band/julkaisut/harjoitukset/2026-09-29/uusi", lang == "fi" and "Uusi biisi" or "New song")
    pub("/band/julkaisut/harjoitukset/2026-09-22/vanha", lang == "fi" and "Vanha biisi" or "Old song")
    pub("/band/julkaisut/harjoitukset/2026-09-15/suljettu", lang == "fi" and "Suljettu biisi" or "Closed song")
    fs.files["/band/julkaisut/harjoitukset/2026-09-29/tulossa/r1/stems/bass.wav"] = "half"
    wm.write_state(fs, "/band/ehdotukset/eero/harjoitukset/2026-09-22/vanha", { song = { id = "s1" }, member = "eero", base_revision = 1, own_fingerprint = "x" })
    local cyc = require("bandcollab.cycles")
    cyc.ensure(fs, b, "/band", b.libraries[1], "2026-09-15", "T"); cyc.close(fs, b, "/band", b.libraries[1], "2026-09-15", "T2")
  end
  local sess = workspace_picker.new(fs, b, "/band", s, "eero", { create = function() end, open = function() end })
  sess:refresh()
  return sess, s
end
scenario("picker_fi", "fi", 620, 420, function(_)
  local sess, s = picker_world("fi", true)
  return function(ctx) return picker_view.draw(ctx, sess) end, s:t("ui.picker.title")
end)
scenario("picker_empty_en", "en", 620, 220, function(_)
  local sess, s = picker_world("en", false)
  return function(ctx) return picker_view.draw(ctx, sess) end, s:t("ui.picker.title")
end)

-- the producer's proposals panel: fake operations with canned data
local function import_world(lang, opts)
  opts = opts or {}
  local s = S(lang)
  local fi = lang == "fi"
  local entries = {
    { member = "eero", member_name = "Eero", title = fi and "Yö kuka minä" or "Night song", slug = "biisi", sent = "2026-09-29 20:41", song_id = "s1",
      delivery = "d1", dir = "/d", pub_dir = "/pub", note = { summary = fi and "Tiukennettu säkeistö 2" or "Tightened verse 2" }, base = 5, current = 8, outdated = true },
    { member = "pia", member_name = "Pia", title = fi and "Yö kuka minä" or "Night song", slug = "biisi", sent = "2026-09-30 18:05", song_id = "s1",
      delivery = "d2", dir = "/d2", pub_dir = "/pub", note = { summary = fi and "Uusi laulu kertosäkeeseen" or "New chorus vocal" }, base = 8, current = 8, outdated = false },
  }
  local env = { undo_id = opts.undo_id }
  env.inbox = function() return { pending = opts.empty and {} or entries, accepted = {}, arriving = opts.arriving and { { member = "aino", member_name = "Aino", delivery = "d9" } } or {} } end
  env.master = function() return { song = { id = "s1" }, file = "/m.rpp", dir = "/m" } end
  env.can_undo = function() return env.undo_id end
  env.preview = function(_, _, _, _, entry)
    return { note = entry.note, base = entry.base, current = entry.current,
      folders = { { role = "drums", label = fi and "Rummut" or "Drums", before = { tracks = 2, items = 1 }, after = { tracks = 3, items = 4 } },
                  { role = "bass", label = fi and "Basso" or "Bass", ignored = true } },
      warnings = opts.warnings and {
        { code = "import_outdated", severity = "warning", vars = { base = 5, current = 8 } },
        { code = "import_conflict", severity = "warning", detail = fi and "Rummut" or "Drums" },
        { code = "import_tempo", severity = "warning" },
        { code = "import_longer", severity = "info", detail = "3:16 / 3:08" } } or {},
      timing = { master = { bpm = 120, length = 188 }, proposal = { bpm = opts.warnings and 124 or 120, length = 196 }, tempo_differs = opts.warnings } }
  end
  env.import = function() return nil end
  env.undo = function() return nil end
  env.publications_dir = function() return "/pub" end
  local b = receive_band(lang)
  b.producer = "aino"
  local sess = import_session.new(memfs.new(), b, "/band", s, "aino", env)
  sess:refresh()
  return sess, s, entries
end
scenario("import_inbox_fi", "fi", 680, 330, function(_)
  local sess, s = import_world("fi", { arriving = true })
  return function(ctx) return import_view.draw(ctx, sess) end, s:t("ui.import.title")
end)
scenario("import_review_fi", "fi", 680, 600, function(_)
  local sess, s, entries = import_world("fi", { warnings = true })
  sess:review(entries[1])
  return function(ctx) return import_view.draw(ctx, sess) end, s:t("ui.import.title")
end)
scenario("import_review_clean_en", "en", 680, 520, function(_)
  local sess, s, entries = import_world("en")
  sess:review(entries[2])
  return function(ctx) return import_view.draw(ctx, sess) end, s:t("ui.import.title")
end)
scenario("import_done_fi", "fi", 680, 330, function(_)
  local sess, s = import_world("fi", { undo_id = "d1", empty = true })
  sess.result = { ok = true, text = s:t("ui.import.imported") }
  return function(ctx) return import_view.draw(ctx, sess) end, s:t("ui.import.title")
end)

local errors = {}
local names = {}
for _, sc in ipairs(scenarios) do names[#names + 1] = sc.name end
local f = io.open(dir .. "/scenarios.txt", "w"); f:write(table.concat(names, "\n"), "\n"); f:close()

local index, ctx, draw, title, frames, started

local function exists(path) local h = io.open(path, "r"); if h then h:close(); return true end end

local function finish()
  local out = io.open(dir .. "/errors.txt", "w")
  out:write(#errors == 0 and "no errors\n" or table.concat(errors, "\n") .. "\n")
  out:close()
  local done = io.open(dir .. "/finished", "w"); done:write("ok\n"); done:close()
  safe_quit()
end

local function start(i)
  local sc = scenarios[i]
  ctx = reaper.ImGui_CreateContext("shots_" .. sc.name)
  draw, title = sc.make(S(sc.lang))
  frames, started = 0, reaper.time_precise()
end

local function loop()
  local sc = scenarios[index]
  reaper.ImGui_SetNextWindowSize(ctx, sc.w, sc.h, reaper.ImGui_Cond_Always())
  reaper.ImGui_SetNextWindowPos(ctx, 60, 60, reaper.ImGui_Cond_Always())
  local visible = reaper.ImGui_Begin(ctx, title, true, reaper.ImGui_WindowFlags_NoCollapse())
  if visible then
    local ok, err = pcall(draw, ctx)
    if not ok then errors[#errors + 1] = sc.name .. ": " .. tostring(err) end
    reaper.ImGui_End(ctx)
  end
  frames = frames + 1
  if frames == 30 then
    local r = io.open(dir .. "/ready_" .. sc.name, "w"); r:write(title, "\n"); r:close()
  end
  if exists(dir .. "/ack_" .. sc.name) or reaper.time_precise() - started > 20 then
    index = index + 1
    if index > #scenarios then finish(); return end
    start(index)
  end
  reaper.defer(loop)
end

index = 1
start(1)
reaper.defer(loop)
