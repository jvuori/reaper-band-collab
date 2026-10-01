-- Keeping a workspace in step with the band, in REAPER (run through tests/reaper_runner.lua).
local t = require("luatest")
local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

local F = require("reaper_fixture")
local band, published, republish, render_folder, cleanup, NOW = F.band, F.published, F.republish, F.render_folder, F.cleanup, F.NOW

local function modules()
  return require("bandcollab.workspace"), require("bandcollab.workspace_sync"), require("bandcollab.projectmodel"),
    require("bandcollab.projects"), require("bandcollab.workspace_model")
end

-- the member's workspace (Eero owns the drums; Aino's bass arrives as a stem)
local function make_workspace(fx, song)
  local workspace = modules()
  return assert(workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW }))
end

local function drums_track(pm, proj) return pm.role_folders(proj)[2].track end

t.test("an open workspace is recognized, and a master project is not", function()
  need_reaper()
  local _, sync, _, projects = modules()
  local fx, song = published()
  t.eq(sync.identify(fx.fs, fx.proj), nil, "the master is not a workspace")
  local ws = make_workspace(fx, song)
  local found = sync.identify(fx.fs, ws.proj)
  t.truthy(found); t.eq(found.dir, ws.dir); t.eq(found.state.member, "eero")
  projects.close_tab(ws.proj)
  cleanup(fx)
end)

t.test("the four sync states show up as the member and the producer change things", function()
  need_reaper()
  local _, sync, pm, projects = modules()
  local fx, song, S = published()
  local ws = make_workspace(fx, song)
  local function kind() return sync.status(fx.fs, band, fx.band_folder, ws).sync.kind end

  t.eq(kind(), "none")                                                           -- all current
  local own = drums_track(pm, ws.proj)
  reaper.GetSetMediaTrackInfo_String(own, "P_NAME", "changed by the member", true)
  t.eq(kind(), "up")                                                             -- only own changes
  republish(fx, S)                                                               -- the producer publishes r2
  t.eq(kind(), "both")                                                           -- fetch first, then propose
  reaper.GetSetMediaTrackInfo_String(own, "P_NAME", "Drums - Eero", true)
  local status = sync.status(fx.fs, band, fx.band_folder, ws)
  t.eq(status.sync.kind, "down")                                                 -- only the master is newer
  t.eq(status.latest, 2); t.eq(status.base, 1)

  projects.save_bound(ws.proj); projects.close_tab(ws.proj)
  cleanup(fx)
end)

t.test("looking around in the workspace (selecting things) is not a change", function()
  need_reaper()
  local _, sync, pm, projects = modules()
  local fx, song = published()
  local ws = make_workspace(fx, song)
  reaper.SelectProjectInstance(ws.proj)
  reaper.SetTrackSelected(drums_track(pm, ws.proj), true)
  reaper.SelectAllMediaItems(ws.proj, true)
  t.eq(sync.status(fx.fs, band, fx.band_folder, ws).sync.kind, "none")
  projects.save_bound(ws.proj); projects.close_tab(ws.proj)
  cleanup(fx)
end)

t.test("fetching replaces the others' stems and the timing, and leaves the member's own work exactly as it was", function()
  need_reaper()
  local workspace, sync, pm, projects, wm = modules()
  local fx, song, S = published()
  local ws = make_workspace(fx, song)

  -- the member works: moves his own item, and saves
  local drums = pm.role_folders(ws.proj)[2]
  local item = reaper.GetTrackMediaItem(reaper.GetTrack(ws.proj, drums.index), 0)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0.5)
  projects.save_bound(ws.proj)
  local own_before = workspace.fingerprint(ws.proj, band, "eero")

  -- the producer lowers the bass and changes the tempo, and publishes r2
  local song2 = republish(fx, S, function(master)
    reaper.SetMediaTrackInfo_Value(pm.role_folders(master)[1].track, "D_VOL", 0.25) -- -12 dB instead of -6 dB
    reaper.SetCurrentBPM(master, 133, false)
  end)
  t.eq(song2.latest, 2)

  local result, code, detail = sync.fetch(fx.fs, band, fx.band_folder, ws, { epoch = 1000000, now = NOW })
  t.truthy(result, tostring(code) .. " " .. tostring(detail))
  t.eq(result.from, 1); t.eq(result.to, 2)

  -- the stem now sounds like the producer's new mix (0.5 tone x 0.25 folder fader = 0.125), not the old 0.25
  local folders = pm.role_folders(ws.proj)
  t.eq(#folders, 2); t.eq(folders[1].role, "bass"); t.eq(folders[2].role, "drums", "the role order must be kept")
  t.eq(pm.get_marker(folders[1].track, pm.KEY_STEM), "1")
  local out = ws.dir .. "/check"
  fx.fs.mkdirs(out)
  local bass = render_folder(ws.proj, folders[1].track, out, "bass")
  local published_peak = F.analyze(song2.dir .. "/r2/stems/bass.wav").peak
  t.truthy(published_peak < 0.2, "the producer's new mix is quieter than r1's 0.25: " .. published_peak)
  t.truthy(math.abs(bass.peak - published_peak) < 0.01,
    string.format("the fetched stem must play as published (%.4f), it peaks at %.4f", published_peak, bass.peak))

  -- the member's own folder is exactly as it was, including where he had moved his item
  t.eq(workspace.fingerprint(ws.proj, band, "eero"), own_before, "own work changed by the fetch")
  local moved = reaper.GetTrackMediaItem(reaper.GetTrack(ws.proj, folders[2].index), 0)
  t.truthy(math.abs(reaper.GetMediaItemInfo_Value(moved, "D_POSITION") - 0.5) < 0.001)

  -- timing, markers of state, and files
  t.truthy(math.abs(reaper.GetProjectTimeSignature2(ws.proj) - 133) < 0.01)
  t.eq(pm.get_project_marker(ws.proj, "base_revision"), "2")
  t.eq(wm.read_state(fx.fs, ws.dir).base_revision, 2)
  t.truthy(fx.fs.exists(ws.dir .. "/work/stems/r1/bass.wav"), "the old stem stays for undo")
  t.truthy(fx.fs.exists(ws.dir .. "/work/stems/r2/bass.wav"))
  t.eq(reaper.IsProjectDirty(ws.proj), 0, "the fetched workspace is saved")
  local last = reaper.GetTrack(ws.proj, reaper.CountTracks(ws.proj) - 1)
  t.eq(pm.get_marker(last, pm.KEY_STEM), "reference")

  -- and he still has his own changes to send
  t.eq(sync.status(fx.fs, band, fx.band_folder, ws).sync.kind, "up")
  projects.close_tab(ws.proj)
  cleanup(fx)
end)

t.test("a lengthened song is flagged as a structure change on fetch; an unchanged one is not", function()
  need_reaper()
  local _, sync, pm, projects = modules()
  local fx, song, S = published()
  local ws = make_workspace(fx, song)

  republish(fx, S, function(master)   -- the chorus gets longer: a later item extends the song
    local drums = pm.role_folders(master)[2]
    reaper.SetMediaItemInfo_Value(reaper.GetTrackMediaItem(reaper.GetTrack(master, drums.index), 0), "D_POSITION", 5)
  end)
  local r2 = assert(sync.fetch(fx.fs, band, fx.band_folder, ws, { epoch = 1000000, now = NOW }))
  t.truthy(r2.structure.changed)
  t.truthy(table.concat(r2.structure.reasons, ","):find("length"))

  republish(fx, S)                    -- an ordinary republish, nothing structural
  local r3 = assert(sync.fetch(fx.fs, band, fx.band_folder, ws, { epoch = 2000000, now = NOW }))
  t.falsy(r3.structure.changed)
  t.eq(#r3.structure.reasons, 0)
  projects.close_tab(ws.proj)
  cleanup(fx)
end)

t.test("undo puts the workspace back as it was before the last fetch, and only once", function()
  need_reaper()
  local workspace, sync, pm, projects, wm = modules()
  local fx, song, S = published()
  local ws = make_workspace(fx, song)
  local before = workspace.fingerprint(ws.proj, band, "eero")
  local tempo_before = reaper.GetProjectTimeSignature2(ws.proj)
  local tabs = 0; while reaper.EnumProjects(tabs) do tabs = tabs + 1 end

  republish(fx, S, function(master)
    reaper.SetMediaTrackInfo_Value(pm.role_folders(master)[1].track, "D_VOL", 0.25)
    reaper.SetCurrentBPM(master, 133, false)
  end)
  assert(sync.fetch(fx.fs, band, fx.band_folder, ws, { epoch = 1000000, now = NOW }))
  t.eq(wm.read_state(fx.fs, ws.dir).base_revision, 2)

  local undone, code = sync.undo_fetch(fx.fs, ws)
  t.truthy(undone, tostring(code))
  t.eq(undone.restored, 1)
  t.eq(wm.read_state(fx.fs, ws.dir).base_revision, 1)
  t.eq(pm.get_project_marker(ws.proj, "base_revision"), "1")
  t.truthy(math.abs(reaper.GetProjectTimeSignature2(ws.proj) - tempo_before) < 0.01, "the tempo must be back")
  t.eq(workspace.fingerprint(ws.proj, band, "eero"), before)
  local tabs_after = 0; while reaper.EnumProjects(tabs_after) do tabs_after = tabs_after + 1 end
  t.eq(tabs_after, tabs, "undo must reuse the workspace's tab, not open another")

  local out = ws.dir .. "/check2"
  fx.fs.mkdirs(out)
  local bass = render_folder(ws.proj, pm.role_folders(ws.proj)[1].track, out, "bass")
  t.truthy(math.abs(bass.peak - 0.25) < 0.01, "the old bass stem must be back, it peaks at " .. bass.peak)

  local again, code2 = sync.undo_fetch(fx.fs, ws)
  t.eq(again, nil); t.eq(code2, "nothing_to_undo")

  -- fetching again works and can be undone again
  local refetch = sync.fetch(fx.fs, band, fx.band_folder, ws, { epoch = 2000000, now = NOW })
  t.truthy(refetch); t.eq(refetch.to, 2)
  t.truthy(sync.undo_fetch(fx.fs, ws))
  projects.close_tab(ws.proj)
  cleanup(fx)
end)

t.test("a fetch is refused when unsaved, when nothing is newer, or when the publication is damaged, and changes nothing", function()
  need_reaper()
  local workspace, sync, pm, projects, wm = modules()
  local fx, song, S = published()
  local ws = make_workspace(fx, song)

  local nothing, code0 = sync.fetch(fx.fs, band, fx.band_folder, ws, { epoch = 1 })
  t.eq(nothing, nil); t.eq(code0, "nothing_newer")

  local song2 = republish(fx, S)
  reaper.SelectProjectInstance(ws.proj)
  reaper.GetSetMediaTrackInfo_String(drums_track(pm, ws.proj), "P_NAME", "unsaved change", true)
  reaper.MarkProjectDirty(ws.proj) -- (changes made through the API do not mark the project by themselves)
  local unsaved, code1 = sync.fetch(fx.fs, band, fx.band_folder, ws, { epoch = 2 })
  t.eq(unsaved, nil); t.eq(code1, "project_unsaved")
  projects.save_bound(ws.proj)

  local stem = song2.dir .. "/r2/stems/bass.wav"
  local good = fx.fs.read_all(stem)
  fx.fs.write_all(stem, good:sub(1, 800))
  local project_before = fx.fs.read_all(ws.file)
  local damaged, code2, path2 = sync.fetch(fx.fs, band, fx.band_folder, ws, { epoch = 3 })
  t.eq(damaged, nil); t.eq(code2, "size_mismatch"); t.eq(path2, "stems/bass.wav")
  t.eq(wm.read_state(fx.fs, ws.dir).base_revision, 1)
  t.eq(fx.fs.read_all(ws.file), project_before, "the workspace file must be untouched")
  t.eq(#(fx.fs.list(wm.backups_dir(ws.dir)) or {}), 0, "no backup for a fetch that never started")
  fx.fs.write_all(stem, good)
  projects.close_tab(ws.proj)
  cleanup(fx)
end)
