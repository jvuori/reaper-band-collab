-- The route for a member without a connection (run through tests/reaper_runner.lua): their band
-- folder is a plain local folder, and publications and deliveries travel on removable media.
local t = require("luatest")
local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

local F = require("reaper_fixture")
local band, published, cleanup, NOW = F.band, F.published, F.cleanup, F.NOW

local function tree(fs, dir, out, base)
  out, base = out or {}, base or dir
  for _, e in ipairs(fs.list(dir) or {}) do
    local p = dir .. "/" .. e.name
    if e.is_dir then tree(fs, p, out, base) else out[p:sub(#base + 2)] = fs.read_all(p) end
  end
  return out
end

t.test("a member with a local band folder can work from copied publications and hand back a delivery unchanged", function()
  need_reaper()
  local workspace, sync = require("bandcollab.workspace"), require("bandcollab.workspace_sync")
  local projects, pm = require("bandcollab.projects"), require("bandcollab.projectmodel")
  local songs_list, deliveries = require("bandcollab.songs_list"), require("bandcollab.deliveries")
  local manifest, copytree = require("bandcollab.manifest"), require("bandcollab.copytree")
  local bandfile = require("bandcollab.bandfile")

  local fx, song = published()
  local fs = fx.fs
  local producer_folder = fx.band_folder
  local offline_folder = fx.root .. "/offline-band"             -- the member's own local folder

  -- 1. the producer puts band.json and the publications on a stick; the member copies them home
  local stick = fx.root .. "/usb-stick"
  assert(copytree.copy(fs, producer_folder .. "/publications", stick .. "/publications"))
  assert(fs.write_all(stick .. "/band.json", fs.read_all(producer_folder .. "/band.json")))
  assert(copytree.copy(fs, stick .. "/publications", offline_folder .. "/publications"))
  assert(fs.write_all(offline_folder .. "/band.json", fs.read_all(stick .. "/band.json")))
  for _, d in ipairs({ "producer", "proposals" }) do fs.mkdirs(offline_folder .. "/" .. d) end

  -- 2. the same screens work on the local folder: the song is offered, a workspace is made, work is done
  local offline_band = assert(bandfile.read(fs, offline_folder))
  local found = songs_list.list(fs, offline_band, offline_folder)
  t.eq(#found.songs, 1, "the copied publication must be offered")
  local ws = assert(workspace.create(fs, offline_band, offline_folder, "eero", found.songs[1], { now = NOW }))
  local drums = pm.role_folders(ws.proj)[2]
  local item = reaper.GetTrackMediaItem(reaper.GetTrack(ws.proj, drums.index), 0)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0.4)
  projects.save_bound(ws.proj)

  -- 3. he sends: a complete delivery appears in his local outbox
  local sent = assert(sync.send(fs, offline_band, offline_folder, ws, { note = { summary = "offline take" }, epoch = 1000000, now = NOW }))
  t.truthy(manifest.verify(fs, sent.dir))

  -- 4. the delivery folder goes on a stick and into the producer's band folder, at the same place
  local carried = fx.root .. "/usb-stick/" .. sent.id
  assert(copytree.copy(fs, sent.dir, carried))
  local target = producer_folder .. "/proposals/eero/rehearsals/2026-09-29/" .. song.slug .. "/outbox/" .. sent.id
  assert(copytree.copy(fs, carried, target))

  -- 5. it arrives complete and byte for byte the same, and the producer's side sees it as a delivery
  t.truthy(manifest.verify(fs, target), "the delivery must verify after travelling")
  local original, arrived = tree(fs, sent.dir), tree(fs, target)
  local count = 0
  for name, bytes in pairs(original) do
    t.truthy(arrived[name] ~= nil, "missing after the trip: " .. name)
    t.eq(arrived[name], bytes, "changed on the way: " .. name)
    count = count + 1
  end
  for name in pairs(arrived) do t.truthy(original[name] ~= nil, "extra file after the trip: " .. name) end
  t.truthy(count >= 5, "the delivery should hold several files, it held " .. count)
  local listed = deliveries.latest(fs, producer_folder .. "/proposals/eero/rehearsals/2026-09-29/" .. song.slug .. "/outbox")
  t.eq(listed.id, sent.id)
  t.eq(deliveries.read(fs, listed.dir).note.summary, "offline take")

  -- 5b. the producer takes the carried delivery into the master, unchanged: his timing comes through
  local importer, inbox = require("bandcollab.importer"), require("bandcollab.inbox")
  local strings = require("bandcollab.strings")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  local master = assert(importer.identify_master(fs, fx.proj))
  local entry = inbox.list(fs, band, producer_folder).pending[1]
  t.eq(entry.delivery, sent.id, "the carried delivery must show up in the producer's inbox")
  t.eq(entry.note.summary, "offline take")
  local imported, icode, idetail = importer.import(fs, band, producer_folder, master, entry, S, { epoch = 2000000, now = NOW })
  t.truthy(imported, tostring(icode) .. " " .. tostring(idetail))
  local master_item = reaper.GetTrackMediaItem(reaper.GetTrack(master.proj, pm.role_folders(master.proj)[2].index), 0)
  t.truthy(math.abs(reaper.GetMediaItemInfo_Value(master_item, "D_POSITION") - 0.4) < 0.001, "the offline member's timing must reach the master")
  t.eq(deliveries.status(fs, entry.pub_dir, sent.id), "accepted")

  -- 6. a truncated copy (a stick removed too early) is refused, not accepted
  local broken = fx.root .. "/broken/" .. sent.id
  assert(copytree.copy(fs, sent.dir, broken))
  local chunk = broken .. "/own/drums/tracks.chunk"
  fs.write_all(chunk, fs.read_all(chunk):sub(1, 100))
  local ok, problems = manifest.verify(fs, broken)
  t.falsy(ok); t.eq(problems[1].code, "size_mismatch")

  projects.close_tab(ws.proj)
  cleanup(fx)
end)
