-- Publishes a real project in REAPER (run through tests/reaper_runner.lua); skipped in plain Lua.
-- The project has two role folders with real audio, folder processing and master-bus processing,
-- so the levels of the rendered files show what is and is not baked in.
local t = require("luatest")
local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

local F = require("reaper_fixture")
local band, write_tone, analyze, read, fixture, cleanup, NOW = F.band, F.write_tone, F.analyze, F.read, F.fixture, F.cleanup, F.NOW

t.test("a publication has a stem per role folder with folder processing baked in and the master bus left out", function()
  need_reaper()
  local publisher, strings = require("bandcollab.publisher"), require("bandcollab.strings")
  local manifest = require("bandcollab.manifest")
  local json = require("bandcollab.json")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  local fx = fixture()

  local result, code, detail = publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { note = { summary = "First mix", body = "Bass a bit louder." }, now = NOW })
  t.truthy(result, tostring(code) .. " " .. tostring(detail))
  t.eq(result.revision, 1)
  local dir = result.dir
  t.eq(dir, fx.band_folder .. "/publications/rehearsals/2026-09-29/" .. fx.entry.slug .. "/r1")

  local bass, drums, mix = analyze(dir .. "/stems/bass.wav"), analyze(dir .. "/stems/drums.wav"), analyze(dir .. "/reference.wav")
  -- tone 0.5 through a -6 dB folder fader = 0.25; through a -6 dB folder effect = 0.25
  t.truthy(math.abs(bass.peak - 0.25) < 0.01, "bass stem peak " .. bass.peak)
  t.truthy(math.abs(drums.peak - 0.25) < 0.01, "drums stem peak " .. drums.peak)
  -- the master bus is -20 dB (x0.1): stems must not contain it, the reference mix must
  t.truthy(mix.peak > 0.02 and mix.peak < 0.06, "reference mix peak " .. mix.peak)
  t.truthy(mix.peak < bass.peak / 3, "the reference mix must be quieter than a stem (master bus applied)")
  -- every file is as long as the project
  t.truthy(math.abs(bass.seconds - mix.seconds) < 0.01 and math.abs(drums.seconds - mix.seconds) < 0.01)
  t.truthy(math.abs(mix.seconds - 3) < 0.05, "length " .. mix.seconds)
  t.eq(bass.channels, 2)

  -- publication data
  local info = json.decode(fx.fs.read_all(dir .. "/publication.json"))
  t.eq(info.revision, 1); t.eq(info.song.title, "Test Song"); t.eq(info.note.summary, "First mix")
  t.eq(#info.roles, 2); t.eq(info.roles[1].id, "bass"); t.eq(info.roles[1].owner, "aino"); t.eq(info.roles[2].owner, "eero")
  t.falsy(info.structure.changed, "the first revision has nothing to change from")
  local timing = json.decode(fx.fs.read_all(dir .. "/timing.json"))
  t.truthy(math.abs(timing.length - 3) < 0.05)

  -- the publication is complete and verifiable
  local ok, problems = manifest.verify(fx.fs, dir)
  t.truthy(ok, problems[1] and (problems[1].code .. " " .. tostring(problems[1].path)))

  -- the note reached the change log
  local log = fx.fs.read_all(result.pub_dir .. "/CHANGELOG.md")
  t.truthy(log, "no change log written")
  t.truthy(log:find("First mix", 1, true)); t.truthy(log:find("Bass a bit louder.", 1, true))
  t.truthy(log:find("r1 - 2026-09-29 22:00 - Publication (Aino)", 1, true))
  cleanup(fx)
end)

t.test("each member's own tracks and media are included, so a workspace can be built from the publication alone", function()
  need_reaper()
  local publisher, strings = require("bandcollab.publisher"), require("bandcollab.strings")
  local rpp = require("bandcollab.rpp")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  local fx = fixture()
  local result = assert(publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { now = NOW }))
  for role, tone in pairs({ bass = "bass-tone.wav", drums = "drum-tone.wav" }) do
    local own = result.dir .. "/own/" .. role
    local chunk = fx.fs.read_all(own .. "/tracks.chunk")
    t.truthy(chunk, "no track chunk for " .. role)
    t.truthy(chunk:find("<TRACK", 1, true))
    local refs = rpp.media_refs(chunk)
    t.eq(#refs, 1)
    t.truthy(refs[1]:match("^media/"), "media path not made relative: " .. refs[1])
    local media = own .. "/" .. refs[1]
    t.truthy(fx.fs.exists(media), "the media file the chunk points to is missing")
    t.eq(fx.fs.size(media), fx.fs.size(fx.band_folder .. "/" .. fx.entry.path .. "/media/" .. tone))
  end
  cleanup(fx)
end)

t.test("publishing leaves the master's render settings, selection and saved state as they were", function()
  need_reaper()
  local publisher, strings = require("bandcollab.publisher"), require("bandcollab.strings")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  local fx = fixture()
  local before = fx.fs.read_all(fx.master_file)
  reaper.SelectProjectInstance(fx.proj)
  local _, pattern = reaper.GetSetProjectInfo_String(fx.proj, "RENDER_PATTERN", "", false)
  local settings = reaper.GetSetProjectInfo(fx.proj, "RENDER_SETTINGS", 0, false)
  local selected = reaper.CountSelectedTracks(fx.proj)
  assert(publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { now = NOW }))
  local _, pattern2 = reaper.GetSetProjectInfo_String(fx.proj, "RENDER_PATTERN", "", false)
  t.eq(pattern2, pattern)
  t.eq(reaper.GetSetProjectInfo(fx.proj, "RENDER_SETTINGS", 0, false), settings)
  t.eq(reaper.CountSelectedTracks(fx.proj), selected)
  t.eq(fx.fs.read_all(fx.master_file), before, "the master file must not be modified by publishing")
  t.eq(reaper.IsProjectDirty(fx.proj), 0, "publishing must not leave the project marked as changed")
  cleanup(fx)
end)

t.test("a second publish after a section was lengthened makes r2, flags the structure, and leaves r1 untouched", function()
  need_reaper()
  local publisher, strings = require("bandcollab.publisher"), require("bandcollab.strings")
  local manifest = require("bandcollab.manifest")
  local json = require("bandcollab.json")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  local fx = fixture()
  local r1 = assert(publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { now = NOW }))

  local function tree(dir)
    local out = {}
    local function walk(d)
      for _, e in ipairs(fx.fs.list(d) or {}) do
        local p = d .. "/" .. e.name
        if e.is_dir then walk(p) else out[p] = fx.fs.read_all(p) end
      end
    end
    walk(dir)
    return out
  end
  local before = tree(r1.dir)

  -- lengthen the song: move the drums item to start later, which extends the project
  reaper.SelectProjectInstance(fx.proj)
  local drums_child = reaper.GetTrack(fx.proj, require("bandcollab.projectmodel").role_folders(fx.proj)[2].index)
  local item = reaper.GetTrackMediaItem(drums_child, 0)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 5)
  reaper.Main_SaveProjectEx(fx.proj, fx.master_file, 0)

  local r2 = assert(publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { now = NOW, note = { summary = "Chorus longer" } }))
  t.eq(r2.revision, 2)
  t.truthy(r2.structure.changed)
  t.truthy(table.concat(r2.structure.reasons, ","):find("length"))
  local info = json.decode(fx.fs.read_all(r2.dir .. "/publication.json"))
  t.eq(info.previous, 1)
  t.truthy(info.structure.changed)

  local after = tree(r1.dir)
  for p, data in pairs(before) do t.eq(after[p], data, "r1 changed: " .. p) end
  for p in pairs(after) do t.truthy(before[p] ~= nil, "r1 gained a file: " .. p) end
  t.truthy(manifest.verify(fx.fs, r1.dir))
  t.truthy(manifest.verify(fx.fs, r2.dir))

  local log = fx.fs.read_all(r2.pub_dir .. "/CHANGELOG.md")
  t.truthy(log:find("**NOTE:**", 1, true), "the structure change must be flagged in the log")
  t.truthy(log:find("Chorus longer", 1, true))
  t.truthy(log:find("Chorus longer", 1, true) < log:find("r1 - ", 1, true), "newest entry first")
  cleanup(fx)
end)

t.test("an unsaved project, an unregistered project and a closed cycle are refused with a clear code", function()
  need_reaper()
  local publisher, strings = require("bandcollab.publisher"), require("bandcollab.strings")
  local cycles, bandfile = require("bandcollab.cycles"), require("bandcollab.bandfile")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  local fx = fixture()

  reaper.SelectProjectInstance(fx.proj)
  reaper.Undo_BeginBlock(); reaper.SetMediaTrackInfo_Value(reaper.GetTrack(fx.proj, 0), "D_VOL", 0.9); reaper.Undo_EndBlock("x", -1)
  reaper.MarkProjectDirty(fx.proj)
  local r, code = publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { now = NOW })
  t.eq(r, nil); t.eq(code, "project_unsaved")
  reaper.SelectProjectInstance(fx.proj)
  reaper.Main_OnCommand(40026, 0) -- File: Save project (Main_SaveProjectEx does not clear the changed flag)
  t.eq(reaper.IsProjectDirty(fx.proj), 0, "the save must clear the changed flag")

  t.truthy(cycles.close(fx.fs, band, fx.band_folder, bandfile.library(band, "rehearsals"), "2026-09-29"))
  local r2, code2 = publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { now = NOW })
  t.eq(r2, nil); t.eq(code2, "cycle_closed")
  t.falsy(fx.fs.exists(fx.band_folder .. "/publications/rehearsals/2026-09-29/" .. fx.entry.slug .. "/r1/valmis"))

  -- a project that was never received has no identity
  reaper.Main_OnCommand(40859, 0)
  local blank = (reaper.EnumProjects(-1))
  local r3, code3 = publisher.publish(fx.fs, band, fx.band_folder, blank, S, { now = NOW })
  t.eq(r3, nil); t.eq(code3, "project_unsaved")
  reaper.SelectProjectInstance(blank); reaper.Main_OnCommand(40860, 0)
  cleanup(fx)
end)

t.test("a workspace can be rebuilt from the publication alone: same folders, owners and audio", function()
  need_reaper()
  local publisher, strings = require("bandcollab.publisher"), require("bandcollab.strings")
  local chunks, pm, copytree = require("bandcollab.chunks"), require("bandcollab.projectmodel"), require("bandcollab.copytree")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  local fx = fixture()
  local result = assert(publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { now = NOW }))

  -- a brand-new project that knows nothing about the master: only the publication is used
  local ws_dir = fx.root .. "/workspace"
  fx.fs.mkdirs(ws_dir .. "/media")
  -- (Relative media paths only resolve in a project that has a file name, and Main_SaveProjectEx does
  -- not give an untitled project one. So the workspace file is saved first and then OPENED, which
  -- is also how the real workspace builder has to do it.)
  reaper.Main_OnCommand(40859, 0)
  local scratch = (reaper.EnumProjects(-1))
  reaper.Main_SaveProjectEx(scratch, ws_dir .. "/ws.rpp", 0)
  reaper.Main_OnCommand(40859, 0)
  reaper.Main_openProject("noprompt:" .. ws_dir .. "/ws.rpp")
  local ws = (reaper.EnumProjects(-1))
  t.eq(publisher.project_file(ws), ws_dir .. "/ws.rpp", "the workspace must be a named project")
  for _, role in ipairs({ "bass", "drums" }) do
    local own = result.dir .. "/own/" .. role
    for _, e in ipairs(fx.fs.list(own .. "/media")) do
      assert(copytree.copy_file(fx.fs, own .. "/media/" .. e.name, ws_dir .. "/media/" .. e.name))
    end
    local list = chunks.split(fx.fs.read_all(own .. "/tracks.chunk"))
    t.eq(#list, 2, "a folder track and one child track")
    for _, c in ipairs(list) do
      local index = reaper.CountTracks(ws)
      reaper.InsertTrackAtIndex(index, false)
      reaper.SetTrackStateChunk(reaper.GetTrack(ws, index), c, false)
    end
  end

  local found = pm.role_folders(ws)
  t.eq(#found, 2)
  t.eq(found[1].role, "bass"); t.eq(found[1].owner, "aino"); t.eq(found[1].children, 1)
  t.eq(found[2].role, "drums"); t.eq(found[2].owner, "eero"); t.eq(found[2].children, 1)
  t.eq(#pm.owned_folders(ws, band, "eero"), 1)

  local items = 0
  for i = 0, reaper.CountTracks(ws) - 1 do
    local track = reaper.GetTrack(ws, i)
    for k = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, k)
      local source = reaper.GetMediaItemTake_Source(reaper.GetActiveTake(item))
      local file = reaper.GetMediaSourceFileName(source)      -- as stored: relative to the project
      local full = file:match("^/") and file or (ws_dir .. "/" .. file)
      t.truthy(fx.fs.exists(full), "audio does not resolve: " .. tostring(full))
      t.truthy(full:find(ws_dir, 1, true), "audio is outside the workspace: " .. tostring(full))
      t.truthy(math.abs(reaper.GetMediaItemInfo_Value(item, "D_LENGTH") - 3) < 0.05)
      items = items + 1
    end
  end
  t.eq(items, 2)

  -- the definitive check: render each rebuilt folder like the publisher does. If it sounds like
  -- the master's stem (fader / effect on the folder, tone of 0.5), audio and processing came through.
  reaper.SelectProjectInstance(ws)
  for _, f in ipairs(found) do
    for i = 0, reaper.CountTracks(ws) - 1 do reaper.SetTrackSelected(reaper.GetTrack(ws, i), false) end
    reaper.SetTrackSelected(f.track, true)
    reaper.GetSetProjectInfo_String(ws, "RENDER_FILE", ws_dir .. "/render", true)
    reaper.GetSetProjectInfo_String(ws, "RENDER_PATTERN", f.role, true)
    reaper.GetSetProjectInfo_String(ws, "RENDER_FORMAT", "ZXZhdxgAAQ==", true)
    reaper.GetSetProjectInfo(ws, "RENDER_SRATE", 48000, true)
    reaper.GetSetProjectInfo(ws, "RENDER_CHANNELS", 2, true)
    reaper.GetSetProjectInfo(ws, "RENDER_BOUNDSFLAG", 1, true)
    reaper.GetSetProjectInfo(ws, "RENDER_TAILFLAG", 0, true)
    reaper.GetSetProjectInfo(ws, "RENDER_SETTINGS", 3, true)
    reaper.Main_OnCommand(42230, 0)
    local rendered = ws_dir .. "/render/" .. f.role .. ".wav"
    t.truthy(fx.fs.exists(rendered), "nothing was rendered for " .. f.role)
    local mine, theirs = analyze(rendered), analyze(result.dir .. "/stems/" .. f.role .. ".wav")
    t.truthy(math.abs(mine.peak - theirs.peak) < 0.005,
      string.format("%s: workspace stem peaks at %.4f but the master's stem at %.4f", f.role, mine.peak, theirs.peak))
    t.truthy(math.abs(mine.seconds - 3) < 0.05, "workspace stem length " .. mine.seconds)
  end
  cleanup(fx) -- (the workspace tabs stay open: closing a changed project would ask a question)
end)

t.test("a real publication is refused without its marker, and with a stem cut short", function()
  need_reaper()
  local publisher, strings = require("bandcollab.publisher"), require("bandcollab.strings")
  local manifest = require("bandcollab.manifest")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  local fx = fixture()
  local result = assert(publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { now = NOW }))
  local dir = result.dir
  t.truthy(manifest.verify(fx.fs, dir))

  local marker = fx.fs.read_all(dir .. "/valmis")
  fx.fs.remove(dir .. "/valmis")
  local ok1, problems1 = manifest.verify(fx.fs, dir)
  t.falsy(ok1); t.eq(problems1[1].code, "missing_marker")
  fx.fs.write_all(dir .. "/valmis", marker)
  t.truthy(manifest.verify(fx.fs, dir))

  local stem = fx.fs.read_all(dir .. "/stems/bass.wav")
  fx.fs.write_all(dir .. "/stems/bass.wav", stem:sub(1, #stem // 2))
  local ok2, problems2 = manifest.verify(fx.fs, dir)
  t.falsy(ok2); t.eq(problems2[1].code, "size_mismatch"); t.eq(problems2[1].path, "stems/bass.wav")
  fx.fs.write_all(dir .. "/stems/bass.wav", stem)
  t.truthy(manifest.verify(fx.fs, dir))

  -- the marker is the last file to appear: nothing in the publication is newer than it (by content order)
  local names = {}
  for _, e in ipairs(fx.fs.list(dir)) do names[#names + 1] = e.name end
  t.truthy(#names >= 5)
  cleanup(fx)
end)
