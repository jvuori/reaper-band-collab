local t = require("luatest")
local wm = require("bandcollab.workspace_model")
local memfs = require("memfs")

local band = { locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" } }

t.test("a member's folders for a song follow library, cycle and slug", function()
  local dir = wm.dir(band, "/band", "eero", { library = "harjoitukset", cycle = "2026-09-29", slug = "biisi" })
  t.eq(dir, "/band/ehdotukset/eero/harjoitukset/2026-09-29/biisi")
  t.eq(wm.dir(band, "/band", "eero", { library = "levytys", slug = "x" }), "/band/ehdotukset/eero/levytys/x")
  t.eq(wm.work_dir(dir), dir .. "/work"); t.eq(wm.outbox_dir(dir), dir .. "/outbox"); t.eq(wm.backups_dir(dir), dir .. "/backups")
  t.eq(wm.project_file(dir, "biisi"), dir .. "/work/biisi.rpp")
end)

t.test("the workspace state round trips, and garbage is treated as absent", function()
  local fs = memfs.new()
  local dir = "/band/ehdotukset/eero/x/y"
  t.eq(wm.read_state(fs, dir), nil)
  t.truthy(wm.write_state(fs, dir, { song = { id = "s1" }, member = "eero", base_revision = 3, own_fingerprint = "abc" }))
  local s = wm.read_state(fs, dir)
  t.eq(s.member, "eero"); t.eq(s.base_revision, 3); t.eq(s.own_fingerprint, "abc"); t.eq(s.schema, 1)
  fs.files[dir .. "/work/workspace.json"] = "{oops"
  t.eq(wm.read_state(fs, dir), nil)
end)

t.test("looking around (selecting, resizing) does not change the fingerprint; editing does", function()
  local base = "<TRACK {A}\nNAME \"Basso\"\nTRACKHEIGHT 0 0 0\n<ITEM\nPOSITION 1.5\nSEL 0\n<SOURCE WAVE\nFILE \"media/a.wav\"\n>\n>\n>"
  local looked = base:gsub("SEL 0", "SEL 1"):gsub("TRACKHEIGHT 0 0 0", "TRACKHEIGHT 120 0 0")
  local moved = base:gsub("POSITION 1.5", "POSITION 2.0")
  local renamed_media = base:gsub("media/a.wav", "media/b.wav")
  local f = wm.fingerprint
  t.eq(f({ base }), f({ looked }))
  t.truthy(f({ base }) ~= f({ moved }))
  t.truthy(f({ base }) ~= f({ renamed_media }))
  t.eq(#f({ base }), 16)
end)

t.test("the fingerprint depends on the order and number of folders", function()
  local a, b = "<TRACK {A}\n>", "<TRACK {B}\n>"
  local f = wm.fingerprint
  t.truthy(f({ a, b }) ~= f({ b, a }))
  t.truthy(f({ a }) ~= f({ a, b }))
  t.truthy(f({ a .. b }) ~= f({ a, b }), "chunk boundaries must count")
end)

t.test("the four sync states", function()
  local state = { base_revision = 3, own_fingerprint = "base" }
  t.eq(wm.sync_state(3, state, "base").kind, "none")
  t.eq(wm.sync_state(4, state, "base").kind, "down")
  t.eq(wm.sync_state(3, state, "edited").kind, "up")
  t.eq(wm.sync_state(4, state, "edited").kind, "both")
  local r = wm.sync_state(4, state, "edited")
  t.truthy(r.master_newer); t.truthy(r.own_changed)
end)

t.test("own changes are counted against what was last sent", function()
  local state = { base_revision = 3, own_fingerprint = "base", sent_fingerprint = "edited" }
  t.eq(wm.sync_state(3, state, "edited").kind, "none", "nothing new since the last proposal")
  t.eq(wm.sync_state(3, state, "edited-again").kind, "up")
  t.eq(wm.sync_state(3, state, "base").kind, "up", "going back to the base is also a change from what was sent")
end)

t.test("no publication at all never counts as a newer master", function()
  t.eq(wm.sync_state(nil, { base_revision = 1, own_fingerprint = "x" }, "x").kind, "none")
end)
