local t = require("luatest")
local guardian = require("bandcollab.guardian")
local songfile = require("bandcollab.songfile")
local wm = require("bandcollab.workspace_model")
local manifest = require("bandcollab.manifest")
local cycles = require("bandcollab.cycles")
local json = require("bandcollab.json")
local strings = require("bandcollab.strings")
local memfs = require("memfs")

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" }, { id = "drums", label = "Rummut" } },
  members = { { id = "aino", name = "Aino", roles = { "bass" } }, { id = "eero", name = "Eero", roles = { "drums" } },
              { id = "pia", name = "Pia", roles = {} } },
  locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" },
  libraries = { { id = "harjoitukset", label = "Harjoitukset", kind = "dated" }, { id = "levytys", label = "Levytys", kind = "flat" } },
}
local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")
local SONG = { library = "harjoitukset", cycle = "2026-09-29", slug = "biisi" }

local function world()
  local fs = memfs.new()
  -- a master
  local master_dir = "/band/tuottaja/harjoitukset/2026-09-29/biisi"
  songfile.write(fs, master_dir, { id = "s0123456789abcdef", title = "Biisi", slug = "biisi", library = "harjoitukset", cycle = "2026-09-29" })
  fs.files[master_dir .. "/biisi.rpp"] = "<REAPER_PROJECT>"
  -- Eero's workspace (based on r1) and a published r1
  local ws_dir = wm.dir(band, "/band", "eero", SONG)
  wm.write_state(fs, ws_dir, { song = { id = "s0123456789abcdef", title = "Biisi", slug = "biisi", library = "harjoitukset", cycle = "2026-09-29" }, member = "eero", base_revision = 1, own_fingerprint = "x" })
  fs.files[wm.project_file(ws_dir, "biisi")] = "<REAPER_PROJECT>"
  local pub = "/band/julkaisut/harjoitukset/2026-09-29/biisi"
  fs.files[pub .. "/r1/a.wav"] = "x"
  manifest.write(fs, pub .. "/r1", manifest.build(fs, pub .. "/r1", { created = "T" }))
  return fs, master_dir .. "/biisi.rpp", wm.project_file(ws_dir, "biisi"), pub
end

local function codes(result) local o = {}; for _, w in ipairs(result.warnings) do o[#o + 1] = w.code .. ":" .. w.severity end; return table.concat(o, ",") end

t.test("an ordinary project never gets a message", function()
  local fs = memfs.new({ ["/home/x/Music/demo/demo.rpp"] = "<REAPER_PROJECT>" })
  local r = guardian.check(fs, band, "/band", "eero", { file = "/home/x/Music/demo/demo.rpp" })
  t.eq(r.info, nil); t.eq(#r.warnings, 0)
  t.eq(guardian.check(fs, band, "/band", "eero", { file = nil }).info, nil)
  t.eq(guardian.check(fs, band, "/band", "eero", { file = "" }).info, nil)
end)

t.test("a member who opens the master is warned strongly; the producer is not", function()
  local fs, master = world()
  t.eq(codes(guardian.check(fs, band, "/band", "eero", { file = master })), "master:strong")
  t.eq(codes(guardian.check(fs, band, "/band", "aino", { file = master })), "")
  t.eq(codes(guardian.check(fs, band, "/band", nil, { file = master })), "master:strong", "an unconfigured machine is not the producer")
  local copy = fs.read_all(master)
  songfile.write(fs, "/home/eero/Desktop/kopio", songfile.read(fs, "/band/tuottaja/harjoitukset/2026-09-29/biisi"))
  t.eq(codes(guardian.check(fs, band, "/band", "eero", { file = "/home/eero/Desktop/kopio/biisi.rpp" })), "master:strong", "a copy of the master is still a master")
end)

t.test("the master warning is written in words that ask, not claim", function()
  local fs, master = world()
  local w = guardian.check(fs, band, "/band", "eero", { file = master }).warnings[1]
  local msg = guardian.text(S, w)
  t.truthy(msg.what:find("pääversio")); t.truthy(msg.action:find("Sulje projekti"))
end)

t.test("someone else's workspace is named, with who they are", function()
  local fs, _, ws = world()
  local r = guardian.check(fs, band, "/band", "pia", { file = ws })
  t.eq(codes(r), "other_workspace:strong")
  local msg = guardian.text(S, r.warnings[1])
  t.truthy(msg.what:find("Eero", 1, true)); t.truthy(msg.what:find("Pia", 1, true))
  t.eq(codes(guardian.check(fs, band, "/band", "aino", { file = ws })), "other_workspace:strong", "the producer too: it is not their workspace")
end)

t.test("one's own workspace, in its place and up to date, gets no message", function()
  local fs, _, ws = world()
  t.eq(codes(guardian.check(fs, band, "/band", "eero", { file = ws })), "")
end)

t.test("a workspace of a closed cycle says proposals are no longer accepted", function()
  local fs, _, ws = world()
  cycles.ensure(fs, band, "/band", band.libraries[1], "2026-09-29", "T")
  cycles.close(fs, band, "/band", band.libraries[1], "2026-09-29", "T2")
  local r = guardian.check(fs, band, "/band", "eero", { file = ws })
  t.eq(codes(r), "closed_cycle:warning")
  t.truthy(guardian.text(S, r.warnings[1]).what:find("suljettu"))
end)

t.test("a workspace based on an older master gets a gentle notice, not a blocking one", function()
  local fs, _, ws, pub = world()
  fs.files[pub .. "/r2/a.wav"] = "y"
  manifest.write(fs, pub .. "/r2", manifest.build(fs, pub .. "/r2", { created = "T" }))
  local r = guardian.check(fs, band, "/band", "eero", { file = ws })
  t.eq(codes(r), "outdated:soft")
  local msg = guardian.text(S, r.warnings[1])
  t.truthy(msg.what:find("r2")); t.truthy(msg.what:find("r1")); t.truthy(msg.action:find("Synkronoi"))
end)

t.test("a workspace that has been moved or copied elsewhere is reported, with where it belongs", function()
  local fs, _, ws = world()
  -- the work folder was copied to the desktop: it still has its state file, but is in the wrong place
  fs.files["/home/eero/Desktop/work/biisi.rpp"] = "<REAPER_PROJECT>"
  fs.files["/home/eero/Desktop/work/workspace.json"] = fs.read_all(wm.work_dir(wm.dir(band, "/band", "eero", SONG)) .. "/workspace.json")
  local r = guardian.check(fs, band, "/band", "eero", { file = "/home/eero/Desktop/work/biisi.rpp" })
  t.eq(codes(r), "misplaced:warning")
  t.eq(r.warnings[1].vars.where, ws)
  t.truthy(guardian.text(S, r.warnings[1]).action:find(ws, 1, true))
end)

t.test("a workspace saved as a lone file (no state beside it) is recognized by its hidden marker", function()
  local fs = memfs.new({ ["/home/eero/Desktop/biisi.rpp"] = "<REAPER_PROJECT>" })
  local r = guardian.check(fs, band, "/band", "eero", { file = "/home/eero/Desktop/biisi.rpp", marker_kind = "workspace" })
  t.eq(codes(r), "misplaced_unknown:warning")
  t.eq(codes(guardian.check(fs, band, "/band", "eero", { file = "/home/eero/Desktop/biisi.rpp" })), "", "without the marker it is just a project")
end)

t.test("a template or an unregistered song is managed but harmless", function()
  local fs = memfs.new({ ["/band/template/song-template.rpp"] = "<REAPER_PROJECT>" })
  local r = guardian.check(fs, band, "/band", "eero", { file = "/band/template/song-template.rpp", marker_kind = "template" })
  t.eq(r.info.role, "managed"); t.eq(#r.warnings, 0)
end)

t.test("each warning is shown once per open, and again after the project is reopened", function()
  local tr = guardian.new_tracker()
  t.truthy(tr:is_new_open("H1", "/a.rpp")); t.falsy(tr:is_new_open("H1", "/a.rpp"))
  t.truthy(tr:should_show("H1", "/a.rpp", "master")); t.falsy(tr:should_show("H1", "/a.rpp", "master"))
  t.truthy(tr:should_show("H1", "/a.rpp", "outdated"), "another warning of the same open is its own")
  t.truthy(tr:is_new_open("H1", "/b.rpp"), "another file in the same tab is a new open")
  t.truthy(tr:should_show("H1", "/b.rpp", "master"))
  -- the first project is closed and later opened again
  tr:forget_closed({ [guardian.key("H1", "/b.rpp")] = true })
  t.truthy(tr:is_new_open("H1", "/a.rpp")); t.truthy(tr:should_show("H1", "/a.rpp", "master"))
  t.falsy(tr:should_show("H1", "/b.rpp", "master"), "still open: still counted as shown")
end)

t.test("the master-opened event is logged in the member's own folder, one line each", function()
  local fs = memfs.new()
  t.truthy(guardian.log_event(fs, band, "/band", "eero", "master", "/band/x.rpp", "2026-10-02T21:40:00+03:00"))
  t.truthy(guardian.log_event(fs, band, "/band", "eero", "master", "/band/y.rpp", "2026-10-02T21:45:00+03:00"))
  local lines = {}
  for l in fs.files["/band/ehdotukset/eero/guardian.log"]:gmatch("[^\n]+") do lines[#lines + 1] = json.decode(l) end
  t.eq(#lines, 2); t.eq(lines[1].code, "master"); t.eq(lines[2].file, "/band/y.rpp")
end)

t.test("every warning has a message in both languages", function()
  local EN = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  for _, c in ipairs({ "master", "other_workspace", "unknown_owner", "closed_cycle", "outdated", "misplaced", "misplaced_unknown" }) do
    for _, part in ipairs({ "what", "action" }) do
      t.truthy(S:has("guardian." .. c .. "." .. part, "fi") and EN:has("guardian." .. c .. "." .. part, "en"), c .. "." .. part)
    end
  end
end)
