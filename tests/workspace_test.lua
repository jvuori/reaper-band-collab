-- Builds a member's workspace from a real publication in REAPER (run through tests/reaper_runner.lua).
local t = require("luatest")
local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

local F = require("reaper_fixture")
local band, analyze, fixture, cleanup, NOW = F.band, F.analyze, F.fixture, F.cleanup, F.NOW

-- master with two roles (bass: Aino, drums: Eero) published as r1; returns everything a test needs
local function published()
  local publisher, strings = require("bandcollab.publisher"), require("bandcollab.strings")
  local songs_list = require("bandcollab.songs_list")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  local fx = fixture()
  assert(publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { now = NOW }))
  local song = songs_list.list(fx.fs, band, fx.band_folder).songs[1]
  return fx, song, S
end

local function render_folder(fx, proj, folder_track, dir, name)
  reaper.SelectProjectInstance(proj)
  for i = 0, reaper.CountTracks(proj) - 1 do reaper.SetTrackSelected(reaper.GetTrack(proj, i), false) end
  reaper.SetTrackSelected(folder_track, true)
  reaper.GetSetProjectInfo_String(proj, "RENDER_FILE", dir, true)
  reaper.GetSetProjectInfo_String(proj, "RENDER_PATTERN", name, true)
  reaper.GetSetProjectInfo_String(proj, "RENDER_FORMAT", "ZXZhdxgAAQ==", true)
  reaper.GetSetProjectInfo(proj, "RENDER_SRATE", 48000, true)
  reaper.GetSetProjectInfo(proj, "RENDER_CHANNELS", 2, true)
  reaper.GetSetProjectInfo(proj, "RENDER_BOUNDSFLAG", 1, true)
  reaper.GetSetProjectInfo(proj, "RENDER_TAILFLAG", 0, true)
  reaper.GetSetProjectInfo(proj, "RENDER_SETTINGS", 3, true)
  reaper.Main_OnCommand(42230, 0)
  return dir .. "/" .. name .. ".wav"
end

t.test("a workspace has the member's own folder as real tracks and everyone else's work as collapsed, locked stems", function()
  need_reaper()
  local workspace, pm, projects = require("bandcollab.workspace"), require("bandcollab.projectmodel"), require("bandcollab.projects")
  local publisher, wm, json = require("bandcollab.publisher"), require("bandcollab.workspace_model"), require("bandcollab.json")
  local fx, song = published()

  local ws, code, detail = workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW, reference_name = "Reference mix" })
  t.truthy(ws, tostring(code) .. " " .. tostring(detail))
  t.eq(ws.dir, fx.band_folder .. "/proposals/eero/rehearsals/2026-09-29/" .. song.slug)
  t.eq(publisher.project_file(ws.proj), ws.file)
  t.eq(reaper.IsProjectDirty(ws.proj), 0, "the finished workspace must not be marked as changed")
  t.eq(pm.get_project_marker(ws.proj, "kind"), "workspace")
  t.eq(pm.get_project_marker(ws.proj, "member"), "eero")
  t.eq(pm.get_project_marker(ws.proj, "base_revision"), "1")

  local folders = pm.role_folders(ws.proj)
  t.eq(#folders, 2)
  local bass, drums = folders[1], folders[2]
  t.eq(bass.role, "bass"); t.eq(drums.role, "drums")

  -- Eero's own folder: real, editable tracks with his own audio
  t.eq(pm.get_marker(drums.track, pm.KEY_STEM), nil)
  t.eq(#pm.owned_folders(ws.proj, band, "eero"), 1)
  local own_item = reaper.GetTrackMediaItem(reaper.GetTrack(ws.proj, drums.index), 0)
  t.truthy(own_item, "the own folder must hold his recording")
  t.eq(reaper.GetMediaItemInfo_Value(own_item, "C_LOCK"), 0.0, "his own items must stay editable")
  local file = reaper.GetMediaSourceFileName((reaper.GetMediaItemTake_Source(reaper.GetActiveTake(own_item))))
  t.truthy(file:find("drums", 1, true), "own audio should be kept apart per role: " .. file)
  local full = file:match("^/") and file or (ws.dir .. "/work/" .. file)   -- REAPER may report either form
  t.truthy(fx.fs.exists(full), "his audio is missing: " .. full)
  t.truthy(full:find(ws.dir .. "/work/", 1, true), "his audio must live inside the workspace: " .. full)

  -- Aino's bass: a collapsed stem whose item is locked
  t.eq(pm.get_marker(bass.track, pm.KEY_STEM), "1")
  t.eq(reaper.GetMediaTrackInfo_Value(bass.track, "I_FOLDERCOMPACT"), 2.0)
  local stem_item = reaper.GetTrackMediaItem(reaper.GetTrack(ws.proj, bass.index), 0)
  t.eq(reaper.GetMediaItemInfo_Value(stem_item, "C_LOCK"), 1.0)
  t.truthy(fx.fs.exists(ws.dir .. "/work/stems/r1/bass.wav"))
  t.eq(reaper.GetMediaTrackInfo_Value(bass.track, "D_VOL"), 1.0, "the folder fader stays free and starts at 0 dB")
  t.eq(#pm.owned_folders(ws.proj, band, "aino"), 1, "ownership still comes from band.json")

  -- the reference mix is there, muted and locked
  local last = reaper.GetTrack(ws.proj, reaper.CountTracks(ws.proj) - 1)
  t.eq(pm.get_marker(last, pm.KEY_STEM), "reference")
  t.eq(reaper.GetMediaTrackInfo_Value(last, "B_MUTE"), 1.0)
  t.eq(reaper.GetMediaItemInfo_Value(reaper.GetTrackMediaItem(last, 0), "C_LOCK"), 1.0)

  -- the state on disk
  local state = wm.read_state(fx.fs, ws.dir)
  t.eq(state.base_revision, 1); t.eq(state.member, "eero"); t.eq(state.song.slug, song.slug)
  t.eq(#state.own_fingerprint, 16)
  t.truthy(state.base_timing.length > 2.9)

  projects.close_tab(ws.proj)
  cleanup(fx)
end)

t.test("the workspace plays like the master: others' stems and his own folder sound as they did", function()
  need_reaper()
  local workspace, pm, projects = require("bandcollab.workspace"), require("bandcollab.projectmodel"), require("bandcollab.projects")
  local fx, song = published()
  local ws = assert(workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW }))
  local folders = pm.role_folders(ws.proj)
  local out = ws.dir .. "/check"
  fx.fs.mkdirs(out)
  local bass = analyze(render_folder(fx, ws.proj, folders[1].track, out, "bass"))
  local drums = analyze(render_folder(fx, ws.proj, folders[2].track, out, "drums"))
  -- the master's stems both peak at 0.25 (tone 0.5 through a -6 dB folder fader / effect)
  t.truthy(math.abs(bass.peak - 0.25) < 0.01, "bass stem in the workspace peaks at " .. bass.peak)
  t.truthy(math.abs(drums.peak - 0.25) < 0.01, "own drums in the workspace peak at " .. drums.peak)
  t.truthy(math.abs(bass.seconds - 3) < 0.05)
  projects.close_tab(ws.proj)
  cleanup(fx)
end)

t.test("new recordings are stored inside the workspace, not somewhere else", function()
  need_reaper()
  local workspace, pm, projects = require("bandcollab.workspace"), require("bandcollab.projectmodel"), require("bandcollab.projects")
  local fx, song = published()
  local ws = assert(workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW }))
  t.eq(pm.recording_path(ws.proj), "media")
  reaper.SelectProjectInstance(ws.proj)
  local resolved = reaper.GetProjectPath()   -- where REAPER would put a new take
  t.truthy(resolved:find(ws.dir .. "/work/media", 1, true), "new takes would go to " .. tostring(resolved))
  projects.close_tab(ws.proj)
  cleanup(fx)
end)

t.test("the tempo and sections of the publication are applied to the workspace", function()
  need_reaper()
  local workspace, pm, projects = require("bandcollab.workspace"), require("bandcollab.projectmodel"), require("bandcollab.projects")
  local publisher = require("bandcollab.publisher")
  local fx, song = published()
  -- give the master a tempo and a section before publishing r2, so the workspace has something to copy
  reaper.SelectProjectInstance(fx.proj)
  reaper.SetCurrentBPM(fx.proj, 133, false)
  reaper.AddProjectMarker2(fx.proj, true, 0.5, 2.0, "verse", -1, 0)
  reaper.SelectProjectInstance(fx.proj); reaper.Main_OnCommand(40026, 0)
  local strings = require("bandcollab.strings")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  assert(publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { now = NOW }))
  song = require("bandcollab.songs_list").list(fx.fs, band, fx.band_folder).songs[1]
  t.eq(song.latest, 2)

  local ws = assert(workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW }))
  local bpm = reaper.GetProjectTimeSignature2(ws.proj)
  t.truthy(math.abs(bpm - 133) < 0.01, "tempo " .. tostring(bpm))
  local ok, is_region, pos, rgnend, name = reaper.EnumProjectMarkers2(ws.proj, 0)
  t.truthy(ok and ok ~= 0, "the section marker must be copied")
  t.eq(name, "verse"); t.truthy(is_region); t.truthy(math.abs(pos - 0.5) < 0.01 and math.abs(rgnend - 2.0) < 0.01)
  projects.close_tab(ws.proj)
  cleanup(fx)
end)

t.test("a workspace is refused for a song that already has one, for a closed cycle, and for a damaged publication", function()
  need_reaper()
  local workspace, projects = require("bandcollab.workspace"), require("bandcollab.projects")
  local cycles, bandfile, wm = require("bandcollab.cycles"), require("bandcollab.bandfile"), require("bandcollab.workspace_model")
  local fx, song = published()

  local damaged = { table.unpack({}) }
  local stem = song.dir .. "/r1/stems/bass.wav"
  local original = fx.fs.read_all(stem)
  fx.fs.write_all(stem, original:sub(1, 1000))
  local nothing, code = workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW })
  t.eq(nothing, nil); t.eq(code, "size_mismatch")
  t.eq(wm.read_state(fx.fs, wm.dir(band, fx.band_folder, "eero", song)), nil, "nothing may be left behind")
  fx.fs.write_all(stem, original)

  local ws = assert(workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW }))
  local again, code2 = workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW })
  t.eq(again, nil); t.eq(code2, "workspace_exists")
  projects.close_tab(ws.proj)

  t.truthy(cycles.close(fx.fs, band, fx.band_folder, bandfile.library(band, "rehearsals"), "2026-09-29"))
  local closed, code3 = workspace.create(fx.fs, band, fx.band_folder, "aino", song, { now = NOW })
  t.eq(closed, nil); t.eq(code3, "cycle_closed")
  cleanup(fx)
end)

t.test("REAPER refuses to edit a locked stem item, while the member's own item can be edited", function()
  need_reaper()
  local workspace, pm, projects = require("bandcollab.workspace"), require("bandcollab.projectmodel"), require("bandcollab.projects")
  local fx, song = published()
  local ws = assert(workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW }))
  local folders = pm.role_folders(ws.proj)
  local stem_track = reaper.GetTrack(ws.proj, folders[1].index)   -- Aino's stem: locked
  local own_track = reaper.GetTrack(ws.proj, folders[2].index)    -- Eero's own recording: free

  local function try_split(track)
    reaper.SelectProjectInstance(ws.proj)
    reaper.SelectAllMediaItems(ws.proj, false)
    reaper.SetMediaItemSelected(reaper.GetTrackMediaItem(track, 0), true)
    reaper.SetEditCurPos(1.0, false, false)
    reaper.Main_OnCommand(40012, 0) -- Item: Split items at edit cursor
    return reaper.CountTrackMediaItems(track)
  end
  t.eq(try_split(stem_track), 1, "a locked stem item must not be split")
  t.eq(try_split(own_track), 2, "the member's own item must be editable (control)")

  projects.save_bound(ws.proj)
  projects.close_tab(ws.proj)
  cleanup(fx)
end)
