-- Sending a member's work in REAPER: the preflight check, fixing stray tracks, frozen deliveries.
-- (run through tests/reaper_runner.lua)
local t = require("luatest")
local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

local F = require("reaper_fixture")
local band, published, cleanup, NOW = F.band, F.published, F.cleanup, F.NOW

local function modules()
  return require("bandcollab.workspace"), require("bandcollab.workspace_sync"), require("bandcollab.projectmodel"),
    require("bandcollab.projects"), require("bandcollab.workspace_model"), require("bandcollab.deliveries"), require("bandcollab.manifest")
end

-- Eero's workspace, with one real change made and saved so that there is something to send
local function ready_workspace(with_change)
  local workspace, _, pm, projects = modules()
  local fx, song = published()
  local ws = assert(workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW }))
  if with_change ~= false then
    local drums = pm.role_folders(ws.proj)[2]
    local item = reaper.GetTrackMediaItem(reaper.GetTrack(ws.proj, drums.index), 0)
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0.25)
    projects.save_bound(ws.proj)
  end
  return fx, ws
end

local function finish(fx, ws)
  local _, _, _, projects = modules()
  projects.save_bound(ws.proj)
  projects.close_tab(ws.proj)
  cleanup(fx)
end

local function codes(pre)
  local out = {}
  for _, p in ipairs(pre.problems) do out[#out + 1] = p.code end
  return table.concat(out, ",")
end

-- an audio item on a track, from a file anywhere
local function add_item(track, file, position)
  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  local source = reaper.PCM_Source_CreateFromFile(file)
  reaper.SetMediaItemTake_Source(take, source)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", position or 0)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", 1)
  return item
end

t.test("with something to send, the preflight is clean; with nothing new, it only says so", function()
  need_reaper()
  local _, sync = modules()
  local fx, ws = ready_workspace(false)
  local none = sync.preflight(fx.fs, band, fx.band_folder, ws)
  t.eq(codes(none), "send_unchanged"); t.falsy(none.blocking)

  local fx2, ws2 = ready_workspace(true)
  local ready = sync.preflight(fx2.fs, band, fx2.band_folder, ws2)
  t.eq(codes(ready), "", "a saved workspace with a real change has nothing to report")
  t.falsy(ready.blocking)
  finish(fx2, ws2); finish(fx, ws)
end)

t.test("an unsaved workspace cannot be sent", function()
  need_reaper()
  local _, sync = modules()
  local fx, ws = ready_workspace()
  reaper.MarkProjectDirty(ws.proj)
  local pre = sync.preflight(fx.fs, band, fx.band_folder, ws)
  t.truthy(pre.blocking); t.truthy(codes(pre):find("project_unsaved"))
  local nothing, code = sync.send(fx.fs, band, fx.band_folder, ws, {})
  t.eq(nothing, nil); t.eq(code, "preflight_failed")
  t.eq(#(fx.fs.list(ws.dir .. "/outbox") or {}), 0, "nothing may be written")
  finish(fx, ws)
end)

t.test("a track outside the member's folder is caught, and moving it in loses nothing", function()
  need_reaper()
  local _, sync, pm = modules()
  local fx, ws = ready_workspace()
  local tone = fx.root .. "/extra-tone.wav"
  F.write_tone(tone, 220, 1)

  -- a loose track with an item, and a loose folder with a child, both created after the folders
  local n = reaper.CountTracks(ws.proj)
  reaper.InsertTrackAtIndex(n, false)
  local loose = reaper.GetTrack(ws.proj, n)
  reaper.GetSetMediaTrackInfo_String(loose, "P_NAME", "loose take", true)
  add_item(loose, tone, 1.0)
  reaper.InsertTrackAtIndex(n + 1, false); reaper.InsertTrackAtIndex(n + 2, false)
  local group, child = reaper.GetTrack(ws.proj, n + 1), reaper.GetTrack(ws.proj, n + 2)
  reaper.GetSetMediaTrackInfo_String(group, "P_NAME", "loose group", true)
  reaper.SetMediaTrackInfo_Value(group, "I_FOLDERDEPTH", 1)
  reaper.SetMediaTrackInfo_Value(child, "I_FOLDERDEPTH", -1)
  add_item(child, tone, 2.0)
  local projects = require("bandcollab.projects")
  projects.save_bound(ws.proj)

  local before = pm.role_folders(ws.proj)[2].children
  local pre = sync.preflight(fx.fs, band, fx.band_folder, ws)
  t.truthy(pre.blocking)
  local problem = pre.problems[1]
  t.eq(problem.code, "send_orphans"); t.eq(problem.detail, 3); t.eq(problem.fix, "move_orphans")
  local refused, code = sync.send(fx.fs, band, fx.band_folder, ws, {})
  t.eq(refused, nil); t.eq(code, "preflight_failed")

  t.eq(sync.fix_orphans(ws.proj, band, "eero"), 3)
  t.eq(#sync.find_orphans(ws.proj), 0, "nothing may be left outside")
  local drums = pm.role_folders(ws.proj)[2]
  t.eq(drums.children, before + 3, "the three tracks are now inside his folder")
  -- the folder structure is still valid: the depths of the whole project add up to zero
  local total = 0
  for _, d in ipairs(pm.depths(ws.proj)) do total = total + d end
  t.eq(total, 0)
  -- both items survived the move
  local items = 0
  for i = drums.index, drums.last do items = items + reaper.CountTrackMediaItems(reaper.GetTrack(ws.proj, i - 1)) end
  t.eq(items, 3, "his recording and the two loose items")
  projects.save_bound(ws.proj)
  t.falsy(sync.preflight(fx.fs, band, fx.band_folder, ws).blocking)
  finish(fx, ws)
end)

t.test("an empty folder and a changed tempo must be confirmed, and can then be sent", function()
  need_reaper()
  local _, sync, pm, projects = modules()
  local fx, ws = ready_workspace()
  -- empty his folder
  local drums = pm.role_folders(ws.proj)[2]
  for i = drums.index, drums.last do
    local track = reaper.GetTrack(ws.proj, i - 1)
    for k = reaper.CountTrackMediaItems(track) - 1, 0, -1 do reaper.DeleteTrackMediaItem(track, reaper.GetTrackMediaItem(track, k)) end
  end
  reaper.SetCurrentBPM(ws.proj, 150, false)
  projects.save_bound(ws.proj)

  local pre = sync.preflight(fx.fs, band, fx.band_folder, ws)
  t.falsy(pre.blocking)
  t.truthy(codes(pre):find("send_empty")); t.truthy(codes(pre):find("send_timing"))
  local nothing, code, detail = sync.send(fx.fs, band, fx.band_folder, ws, {})
  t.eq(nothing, nil); t.eq(code, "preflight_needs_ack"); t.eq(#detail.warnings, 2)

  local partly, code2 = sync.send(fx.fs, band, fx.band_folder, ws, { acknowledged = { send_empty = true } })
  t.eq(partly, nil); t.eq(code2, "preflight_needs_ack")

  -- confirmed: an empty folder (no media at all) can still be exported
  local sent = sync.send(fx.fs, band, fx.band_folder, ws, { acknowledged = { send_empty = true, send_timing = true }, epoch = 1000000 })
  t.truthy(sent)
  t.truthy(fx.fs.exists(sent.dir .. "/own/drums/tracks.chunk"))
  finish(fx, ws)
end)

t.test("audio from outside the workspace is copied into the delivery, and the member is told", function()
  need_reaper()
  local _, sync, pm, projects, _, _, manifest = modules()
  local rpp = require("bandcollab.rpp")
  local fx, ws = ready_workspace()
  local outside = fx.root .. "/somewhere-else/Take Two.wav"
  fx.fs.mkdirs(fx.root .. "/somewhere-else")
  F.write_tone(outside, 330, 1)
  local drums = pm.role_folders(ws.proj)[2]
  add_item(reaper.GetTrack(ws.proj, drums.index), outside, 4.0)
  projects.save_bound(ws.proj)

  local pre = sync.preflight(fx.fs, band, fx.band_folder, ws)
  local info
  for _, p in ipairs(pre.problems) do if p.code == "send_media_outside" then info = p end end
  t.truthy(info, "the member must be told"); t.eq(info.severity, "info"); t.eq(info.detail, 1)
  t.falsy(pre.blocking); t.eq(#pre.warnings, 0, "telling is enough, it needs no confirmation")

  local sent = assert(sync.send(fx.fs, band, fx.band_folder, ws, { epoch = 1000000 }))
  local chunk = fx.fs.read_all(sent.dir .. "/own/drums/tracks.chunk")
  for _, ref in ipairs(rpp.media_refs(chunk)) do
    t.truthy(ref:match("^media/"), "the delivery must not point outside itself: " .. ref)
    t.truthy(fx.fs.exists(sent.dir .. "/own/drums/" .. ref), "missing in the delivery: " .. ref)
  end
  t.eq(#rpp.media_refs(chunk), 2, "his recording and the copied take")
  t.truthy(manifest.verify(fx.fs, sent.dir))
  finish(fx, ws)
end)

t.test("a delivery is complete and frozen, and carries the note, the base revision and only his folders", function()
  need_reaper()
  local _, sync, pm, projects, wm, deliveries, manifest = modules()
  local json = require("bandcollab.json")
  local fx, ws = ready_workspace()
  local sent, code = sync.send(fx.fs, band, fx.band_folder, ws, {
    note = { summary = "Tiukennettu säkeistö 2", body = "Uudet täytteet kohdassa 1:32." }, epoch = 1000000, now = NOW,
  })
  t.truthy(sent, tostring(code))
  t.eq(sent.id, "d19700112T134640Z")
  t.eq(sent.dir, ws.dir .. "/outbox/" .. sent.id)
  t.truthy(manifest.verify(fx.fs, sent.dir))

  local info = deliveries.read(fx.fs, sent.dir)
  t.eq(info.member, "eero"); t.eq(info.base_revision, 1); t.eq(info.song.slug, ws.state.song.slug)
  t.eq(info.note.summary, "Tiukennettu säkeistö 2"); t.eq(info.note.body, "Uudet täytteet kohdassa 1:32.")
  t.eq(#info.roles, 1); t.eq(info.roles[1], "drums")
  t.truthy(info.timing and info.timing.length > 0, "the delivery must carry its timing, for the producer's preview")
  t.truthy(info.timing.bpm > 0)
  t.falsy(fx.fs.exists(sent.dir .. "/own/bass"), "his delivery must not carry Aino's stem or folder")
  t.truthy(fx.fs.exists(sent.dir .. "/own/drums/media"))

  -- frozen: later work in the workspace does not touch what was sent
  local before = fx.fs.read_all(sent.dir .. "/own/drums/tracks.chunk")
  local item = reaper.GetTrackMediaItem(reaper.GetTrack(ws.proj, pm.role_folders(ws.proj)[2].index), 0)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 2.0)
  projects.save_bound(ws.proj)
  t.eq(fx.fs.read_all(sent.dir .. "/own/drums/tracks.chunk"), before)
  t.truthy(manifest.verify(fx.fs, sent.dir))
  t.eq(wm.read_state(fx.fs, ws.dir).sent_fingerprint ~= nil, true)
  finish(fx, ws)
end)

t.test("sending again makes a second delivery; the first is kept and the newer one supersedes it", function()
  need_reaper()
  local _, sync, pm, projects, _, deliveries, manifest = modules()
  local fx, ws = ready_workspace()
  local first = assert(sync.send(fx.fs, band, fx.band_folder, ws, { epoch = 1000000, note = { summary = "first" } }))
  local first_bytes = fx.fs.read_all(first.dir .. "/own/drums/tracks.chunk")

  -- nothing changed: sending again needs a confirmation
  local again, code = sync.send(fx.fs, band, fx.band_folder, ws, { epoch = 1000001 })
  t.eq(again, nil); t.eq(code, "preflight_needs_ack")

  local item = reaper.GetTrackMediaItem(reaper.GetTrack(ws.proj, pm.role_folders(ws.proj)[2].index), 0)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 1.75)
  projects.save_bound(ws.proj)
  local second = assert(sync.send(fx.fs, band, fx.band_folder, ws, { epoch = 1000002, note = { summary = "second" } }))

  local list = deliveries.list(fx.fs, ws.dir .. "/outbox")
  t.eq(#list, 2)
  t.eq(deliveries.latest(fx.fs, ws.dir .. "/outbox").id, second.id)
  t.eq(deliveries.read(fx.fs, list[1].dir).note.summary, "first")
  t.eq(fx.fs.read_all(first.dir .. "/own/drums/tracks.chunk"), first_bytes, "the first delivery must be untouched")
  t.truthy(manifest.verify(fx.fs, first.dir)); t.truthy(manifest.verify(fx.fs, second.dir))

  -- two sends in the same second do not collide
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0.6)
  projects.save_bound(ws.proj)
  local third = assert(sync.send(fx.fs, band, fx.band_folder, ws, { epoch = 1000002 }))
  t.eq(third.id, second.id .. "-2")
  t.eq(#deliveries.list(fx.fs, ws.dir .. "/outbox"), 3)
  finish(fx, ws)
end)

t.test("the status line shows when it was sent and whether the producer has taken it in", function()
  need_reaper()
  local _, sync = modules()
  local json = require("bandcollab.json")
  local fx, ws = ready_workspace()
  t.eq(sync.proposal_status(fx.fs, band, fx.band_folder, ws), nil, "nothing sent yet")
  t.eq(sync.status(fx.fs, band, fx.band_folder, ws).proposal, nil)

  local sent = assert(sync.send(fx.fs, band, fx.band_folder, ws, { epoch = 1000000, now = NOW }))
  local status = sync.proposal_status(fx.fs, band, fx.band_folder, ws)
  t.eq(status.id, sent.id); t.eq(status.sent, "2026-09-29 22:00"); t.eq(status.status, "pending")
  t.eq(sync.status(fx.fs, band, fx.band_folder, ws).sync.kind, "none", "after sending, nothing new is left to send")

  -- the producer records that it took the delivery in
  local pub = fx.band_folder .. "/publications/rehearsals/2026-09-29/" .. ws.state.song.slug
  fx.fs.write_all(pub .. "/imports.json", json.encode({ schema = 1, imports = { { delivery = sent.id, member = "eero", at = "2026-09-30T10:00:00+03:00" } } }))
  t.eq(sync.proposal_status(fx.fs, band, fx.band_folder, ws).status, "accepted")
  finish(fx, ws)
end)
