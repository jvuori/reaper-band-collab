-- Draws each UI screen for a while so that tools/ui_shots.sh can capture the window.
-- It doubles as a smoke test: every frame is drawn under pcall, and errors are recorded.
-- Env: BANDCOLLAB_ROOT (repository root), SHOT_DIR (working directory for signal files).
-- Signal files: ready_<name> (contains the window title) -> the shell captures -> ack_<name>.
local root = assert(os.getenv("BANDCOLLAB_ROOT"), "BANDCOLLAB_ROOT not set")
local dir = assert(os.getenv("SHOT_DIR"), "SHOT_DIR not set")
package.path = table.concat({ root .. "/lib/?.lua", root .. "/ui/?.lua", package.path }, ";")

local strings = require("bandcollab.strings")
local wizard = require("bandcollab.wizard")
local firstrun = require("bandcollab.firstrun")
local messages = require("bandcollab.messages")
local wizard_view = require("wizard_view")
local receive_view = require("receive_view")
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
  reaper.Main_OnCommand(40004, 0)
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
