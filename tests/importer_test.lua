-- The producer's import in REAPER (run through tests/reaper_runner.lua).
local t = require("luatest")
local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

local F = require("reaper_fixture")
local band, published, cleanup, NOW = F.band, F.published, F.cleanup, F.NOW

local function modules()
  return require("bandcollab.importer"), require("bandcollab.inbox"), require("bandcollab.workspace"),
    require("bandcollab.workspace_sync"), require("bandcollab.projects"), require("bandcollab.projectmodel"),
    require("bandcollab.deliveries"), require("bandcollab.manifest")
end

-- Eero (drums) works on his own part and sends it; returns what the producer then sees.
local function proposal()
  local importer, inbox, workspace, sync, projects, pm = modules()
  local fx, song, S = published()
  local ws = assert(workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW }))
  local item = reaper.GetTrackMediaItem(reaper.GetTrack(ws.proj, pm.role_folders(ws.proj)[2].index), 0)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0.4)
  projects.save_bound(ws.proj)
  local sent = assert(sync.send(fx.fs, band, fx.band_folder, ws, {
    note = { summary = "Tiukennettu säkeistö 2", body = "Uudet täytteet." }, epoch = 1000000, now = NOW }))
  projects.close_tab(ws.proj)
  local master = assert(importer.identify_master(fx.fs, fx.proj))
  local entry = inbox.list(fx.fs, band, fx.band_folder).pending[1]
  return fx, S, master, entry, sent
end

local function drums_item(master)
  local pm = require("bandcollab.projectmodel")
  local folder = pm.role_folders(master.proj)[2]
  return reaper.GetTrackMediaItem(reaper.GetTrack(master.proj, folder.index), 0), folder
end

t.test("a master is recognized, and a workspace is not a master", function()
  need_reaper()
  local importer, _, _, _, projects = modules()
  local fx = F.fixture()
  t.truthy(importer.identify_master(fx.fs, fx.proj))
  cleanup(fx)
end)

t.test("the preview shows what will be replaced, the note and the versions, and changes nothing", function()
  need_reaper()
  local importer = modules()
  local fx, S, master, entry = proposal()
  local master_before = fx.fs.read_all(master.file)
  local tree_before = {}
  for _, e in ipairs(fx.fs.list(entry.pub_dir)) do tree_before[e.name] = true end

  local pre, code, detail = importer.preview(fx.fs, band, fx.band_folder, master, entry)
  t.truthy(pre, tostring(code) .. " " .. tostring(detail))
  t.eq(#pre.folders, 1)
  local folder = pre.folders[1]
  t.eq(folder.role, "drums"); t.eq(folder.label, "Drums")
  t.eq(folder.before.tracks, 2); t.eq(folder.before.items, 1)
  t.eq(folder.after.tracks, 2); t.eq(folder.after.items, 1)
  t.falsy(folder.conflict); t.falsy(folder.ignored); t.falsy(folder.missing)
  t.eq(pre.note.summary, "Tiukennettu säkeistö 2"); t.eq(pre.note.body, "Uudet täytteet.")
  t.eq(pre.base, 1); t.eq(pre.current, 1)
  -- nothing to be careful about; the only remark is that his moved item makes the song 0.4 s longer
  for _, w in ipairs(pre.warnings) do t.eq(w.severity, "info", "unexpected warning " .. w.code) end
  t.eq(#pre.warnings, 1); t.eq(pre.warnings[1].code, "import_longer")
  t.falsy(pre.timing.tempo_differs)

  -- looking is not doing: the master, the records and the folders are exactly as before
  t.eq(fx.fs.read_all(master.file), master_before)
  t.falsy(fx.fs.exists(entry.pub_dir .. "/imports.json"))
  t.falsy(fx.fs.exists(master.dir .. "/backups"))
  for _, e in ipairs(fx.fs.list(entry.pub_dir)) do t.truthy(tree_before[e.name], "preview created " .. e.name) end
  cleanup(fx)
end)

t.test("a proposal that is incomplete or damaged is refused before anything is touched", function()
  need_reaper()
  local importer, _, _, _, _, _, _, manifest = modules()
  local fx, S, master, entry = proposal()
  local master_before = fx.fs.read_all(master.file)

  local marker = fx.fs.read_all(entry.dir .. "/valmis")
  fx.fs.remove(entry.dir .. "/valmis")
  local r1, code1 = importer.import(fx.fs, band, fx.band_folder, master, entry, S, { epoch = 2000000, now = NOW })
  t.eq(r1, nil); t.eq(code1, "missing_marker")
  fx.fs.write_all(entry.dir .. "/valmis", marker)

  local chunk = entry.dir .. "/own/drums/tracks.chunk"
  local good = fx.fs.read_all(chunk)
  fx.fs.write_all(chunk, good:sub(1, #good // 2))
  local r2, code2, path2 = importer.import(fx.fs, band, fx.band_folder, master, entry, S, { epoch = 2000000, now = NOW })
  t.eq(r2, nil); t.eq(code2, "size_mismatch"); t.eq(path2, "own/drums/tracks.chunk")
  fx.fs.write_all(chunk, good)

  t.eq(fx.fs.read_all(master.file), master_before)
  t.falsy(fx.fs.exists(master.dir .. "/backups"), "no backup for an import that never started")
  t.falsy(fx.fs.exists(entry.pub_dir .. "/imports.json"))
  cleanup(fx)
end)

t.test("the backup is the first thing written, before any media or the project", function()
  need_reaper()
  local importer = modules()
  local fx, S, master, entry = proposal()
  local writes = {}
  local write_all, open_write = fx.fs.write_all, fx.fs.open_write
  fx.fs.write_all = function(p, d) writes[#writes + 1] = p; return write_all(p, d) end
  fx.fs.open_write = function(p) writes[#writes + 1] = p; return open_write(p) end
  local master_before = fx.fs.read_all(master.file)

  local result = assert(importer.import(fx.fs, band, fx.band_folder, master, entry, S, { epoch = 2000000, now = NOW }))
  t.truthy(writes[1]:find("/backups/", 1, true), "the first write was " .. writes[1])
  t.truthy(writes[1]:find("%.rpp$"), "the first write must be the copy of the master")
  local backup = master.dir .. "/backups/" .. result.backup
  t.eq(fx.fs.read_all(backup .. "/" .. master.file:match("[^/]*$")), master_before, "the backup must be the master exactly as it was")
  t.eq(result.backup, "i19700124T033320Z")   -- 2,000,000 s after the epoch
  cleanup(fx)
end)

t.test("only the proposer's own folders are replaced: whatever else a delivery holds is ignored", function()
  need_reaper()
  local importer, _, _, _, _, pm, _, manifest = modules()
  local wm = require("bandcollab.workspace_model")
  local fx, S, master, entry = proposal()

  -- a delivery made by a modified tool: it also carries Aino's folder, a stem, and a changed tempo
  local d = entry.dir
  local info = require("bandcollab.json").decode(fx.fs.read_all(d .. "/delivery.json"))
  info.roles = { "drums", "bass" }
  info.timing.bpm = 200
  fx.fs.write_all(d .. "/delivery.json", require("bandcollab.json").encode(info, { pretty = true }))
  fx.fs.write_all(d .. "/own/bass/tracks.chunk", "<TRACK {00000000-0000-0000-0000-000000000000}\nNAME \"HACKED BASS\"\n>\n")
  fx.fs.write_all(d .. "/stems/bass.wav", "not audio at all")
  assert(manifest.write(fx.fs, d, manifest.build(fx.fs, d, { kind = "delivery", created = "T" })))   -- a valid manifest for it

  local bass_before = wm.fingerprint({ pm.folder_chunk(master.proj, pm.role_folders(master.proj)[1]) })
  local bpm_before = reaper.GetProjectTimeSignature2(master.proj)
  local tracks_before = reaper.CountTracks(master.proj)

  local pre = assert(importer.preview(fx.fs, band, fx.band_folder, master, entry))
  local ignored
  for _, row in ipairs(pre.folders) do if row.role == "bass" then ignored = row end end
  t.truthy(ignored and ignored.ignored, "Aino's folder in Eero's delivery must be shown as ignored")

  assert(importer.import(fx.fs, band, fx.band_folder, master, entry, S, { epoch = 2000000, now = NOW }))
  local bass_after = wm.fingerprint({ pm.folder_chunk(master.proj, pm.role_folders(master.proj)[1]) })
  t.eq(bass_after, bass_before, "Aino's folder must be untouched")
  t.eq(reaper.GetProjectTimeSignature2(master.proj), bpm_before, "the tempo of the master must not follow the delivery")
  t.eq(reaper.CountTracks(master.proj), tracks_before)
  t.falsy(fx.fs.exists(master.dir .. "/media/" .. entry.delivery .. "/bass"), "nothing of Aino's may be copied in")
  cleanup(fx)
end)

t.test("a change the producer made to the member's folder after the base version is warned about, but can still be accepted", function()
  need_reaper()
  local importer, _, _, _, projects, pm = modules()
  local fx, S, master, entry = proposal()
  -- the producer lowers the drums bus in the master (no new publication yet)
  reaper.SelectProjectInstance(master.proj)
  reaper.SetMediaTrackInfo_Value(pm.role_folders(master.proj)[2].track, "D_VOL", 0.7)
  projects.save_bound(master.proj)

  local pre = assert(importer.preview(fx.fs, band, fx.band_folder, master, entry))
  t.truthy(pre.folders[1].conflict)
  local found
  for _, w in ipairs(pre.warnings) do if w.code == "import_conflict" then found = w end end
  t.truthy(found, "the warning must be listed"); t.eq(found.detail, "Drums")
  local result = importer.import(fx.fs, band, fx.band_folder, master, entry, S, { epoch = 2000000, now = NOW })
  t.truthy(result, "a warning must not block the import")
  cleanup(fx)
end)

t.test("an older base version and a different tempo are warned about", function()
  need_reaper()
  local importer, _, _, _, projects = modules()
  local publisher = require("bandcollab.publisher")
  local fx, S, master, entry = proposal()
  local strings = require("bandcollab.strings")
  F.republish(fx, S)                                    -- the producer has moved on to r2
  reaper.SelectProjectInstance(master.proj)
  reaper.SetCurrentBPM(master.proj, 150, false)         -- and changed the tempo
  projects.save_bound(master.proj)
  local pre = assert(importer.preview(fx.fs, band, fx.band_folder, master, require("bandcollab.inbox").list(fx.fs, band, fx.band_folder).pending[1]))
  local codes = {}
  for _, w in ipairs(pre.warnings) do codes[w.code] = w end
  t.truthy(codes.import_outdated); t.eq(codes.import_outdated.vars.base, 1); t.eq(codes.import_outdated.vars.current, 2)
  t.truthy(codes.import_tempo)
  t.eq(pre.base, 1); t.eq(pre.current, 2)
  cleanup(fx)
end)

t.test("accepting replaces the member's folder with his version, plays as it should, and is recorded", function()
  need_reaper()
  local importer, inbox, _, _, _, pm, deliveries = modules()
  local fx, S, master, entry = proposal()
  local result, code, detail = importer.import(fx.fs, band, fx.band_folder, master, entry, S, { epoch = 2000000, now = NOW })
  t.truthy(result, tostring(code) .. " " .. tostring(detail))
  t.eq(#result.replaced, 1); t.eq(result.replaced[1].role, "drums"); t.eq(result.replaced[1].tracks, 2)

  -- his version is in the master: the item sits where he moved it, the markers are intact
  local item, folder = drums_item(master)
  t.truthy(math.abs(reaper.GetMediaItemInfo_Value(item, "D_POSITION") - 0.4) < 0.001, "his timing must come through")
  t.eq(folder.role, "drums"); t.eq(folder.owner, "eero")
  t.eq(#pm.role_folders(master.proj), 2); t.eq(pm.role_folders(master.proj)[1].role, "bass", "the order of the folders is kept")
  t.eq(reaper.IsProjectDirty(master.proj), 0, "the master is saved")
  t.truthy(fx.fs.exists(master.dir .. "/media/" .. entry.delivery .. "/drums"), "his audio is in the master's media")

  -- and it sounds right (tone 0.5 through the drums folder effect = 0.25)
  local out = master.dir .. "/check"
  fx.fs.mkdirs(out)
  local drums = F.render_folder(master.proj, folder.track, out, "drums")
  t.truthy(math.abs(drums.peak - 0.25) < 0.01, "drums peak " .. drums.peak)

  -- recorded: members see it as taken in, the inbox moves it, it cannot be taken in twice
  t.eq(deliveries.status(fx.fs, entry.pub_dir, entry.delivery), "accepted")
  local listed = inbox.list(fx.fs, band, fx.band_folder)
  t.eq(#listed.pending, 0); t.eq(#listed.accepted, 1)
  local again, code2 = importer.import(fx.fs, band, fx.band_folder, master, entry, S, { epoch = 2000001, now = NOW })
  t.eq(again, nil); t.eq(code2, "already_imported")
  cleanup(fx)
end)

t.test("the log gets an entry with the sent time, the note and what was taken in; the producer may edit the note", function()
  need_reaper()
  local importer = modules()
  local fx, S, master, entry = proposal()
  assert(importer.import(fx.fs, band, fx.band_folder, master, entry, S, {
    epoch = 2000000, now = { display = "2026-10-01 23:05", iso = "2026-10-01T23:05:00+03:00" },
    note = { summary = "Drums tightened in verse 2" },
  }))
  local log = fx.fs.read_all(entry.pub_dir .. "/CHANGELOG.md")
  t.truthy(log:find("2026-10-01 23:05 - Proposal imported (Eero)", 1, true), "heading with the import time and the sender")
  t.truthy(log:find("Drums tightened in verse 2", 1, true), "the producer's edited wording")
  t.falsy(log:find("Tiukennettu säkeistö 2", 1, true), "the original wording must not be logged when it was edited")
  t.truthy(log:find("Sent: 2026-09-29 22:00", 1, true), "the time it was sent")
  t.truthy(log:find("Taken in: 2 tracks (Drums)", 1, true))
  cleanup(fx)
end)

t.test("undo puts the master back exactly as it was, makes the proposal pending again and logs the reversal", function()
  need_reaper()
  local importer, inbox, _, _, _, _, deliveries = modules()
  local fx, S, master, entry = proposal()
  local before = fx.fs.read_all(master.file)
  local tabs = 0; while reaper.EnumProjects(tabs) do tabs = tabs + 1 end

  assert(importer.import(fx.fs, band, fx.band_folder, master, entry, S, { epoch = 2000000, now = NOW }))
  t.truthy(fx.fs.read_all(master.file) ~= before, "the import must have changed the master")
  t.eq(importer.can_undo(fx.fs, master), entry.delivery)

  local undone = importer.undo_import(fx.fs, band, fx.band_folder, master, entry.pub_dir, S, { now = NOW })
  t.truthy(undone); t.eq(undone.delivery, entry.delivery)
  t.eq(fx.fs.read_all(master.file), before, "the master must be identical to its state before the import")
  t.eq(deliveries.status(fx.fs, entry.pub_dir, entry.delivery), "pending")
  t.eq(#inbox.list(fx.fs, band, fx.band_folder).pending, 1)
  local after_tabs = 0; while reaper.EnumProjects(after_tabs) do after_tabs = after_tabs + 1 end
  t.eq(after_tabs, tabs, "undo must reuse the master's tab")
  t.truthy(fx.fs.read_all(entry.pub_dir .. "/CHANGELOG.md"):find("Import undone", 1, true), "the reversal must be logged")

  local item = drums_item(master)
  t.truthy(math.abs(reaper.GetMediaItemInfo_Value(item, "D_POSITION") - 0) < 0.001, "the old drums are back")
  local again, code = importer.undo_import(fx.fs, band, fx.band_folder, master, entry.pub_dir, S, { now = NOW })
  t.eq(again, nil); t.eq(code, "nothing_to_undo_import")

  -- the same proposal can be taken in again afterwards
  t.truthy(importer.import(fx.fs, band, fx.band_folder, master, entry, S, { epoch = 3000000, now = NOW }))
  cleanup(fx)
end)

t.test("an unsaved master, and a proposal for another song, are refused", function()
  need_reaper()
  local importer = modules()
  local json, manifest = require("bandcollab.json"), require("bandcollab.manifest")
  local fx, S, master, entry = proposal()
  reaper.SelectProjectInstance(master.proj)
  reaper.MarkProjectDirty(master.proj)
  local r1, code1 = importer.import(fx.fs, band, fx.band_folder, master, entry, S, { epoch = 2000000, now = NOW })
  t.eq(r1, nil); t.eq(code1, "project_unsaved")
  require("bandcollab.projects").save_bound(master.proj)

  local info = json.decode(fx.fs.read_all(entry.dir .. "/delivery.json"))
  info.song.id = "s0000000000000000"
  fx.fs.write_all(entry.dir .. "/delivery.json", json.encode(info, { pretty = true }))
  assert(manifest.write(fx.fs, entry.dir, manifest.build(fx.fs, entry.dir, { kind = "delivery", created = "T" })))
  local r2, code2 = importer.import(fx.fs, band, fx.band_folder, master, entry, S, { epoch = 2000000, now = NOW })
  t.eq(r2, nil); t.eq(code2, "wrong_song")
  t.falsy(fx.fs.exists(master.dir .. "/backups"))
  cleanup(fx)
end)
