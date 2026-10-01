-- Keeping a member's workspace in step with the band, and sending their work (needs REAPER):
--   status      what is different: is there a newer master, has the member changed anything
--   fetch       "get the master": replace the stems and timing, keep the member's own folders,
--               after backing up the whole workspace; undo_fetch puts everything back
--   preflight   what must be fixed before sending; fix_orphans moves stray tracks into the member's folder
--   send        makes a frozen, timestamped delivery in the outbox
local pm = require("bandcollab.projectmodel")
local projects = require("bandcollab.projects")
local workspace = require("bandcollab.workspace")
local wm = require("bandcollab.workspace_model")
local songs_list = require("bandcollab.songs_list")
local revisions = require("bandcollab.revisions")
local deliveries = require("bandcollab.deliveries")
local ownexport = require("bandcollab.ownexport")
local publisher = require("bandcollab.publisher")
local folders = require("bandcollab.folders")
local manifest = require("bandcollab.manifest")
local timing = require("bandcollab.timing")
local cycles = require("bandcollab.cycles")
local bandfile = require("bandcollab.bandfile")
local changelog = require("bandcollab.changelog")
local copytree = require("bandcollab.copytree")
local inspect = require("bandcollab.inspect")
local chunks = require("bandcollab.chunks")
local rpp = require("bandcollab.rpp")
local json = require("bandcollab.json")
local path = require("bandcollab.path")

local M = {}

-- identify(fs, proj) -> ws | nil: is this open project one of the member's workspaces?
function M.identify(fs, proj)
  local file = publisher.project_file(proj)
  if not file or pm.get_project_marker(proj, pm.KEY_KIND) ~= "workspace" then return nil end
  local dir = path.dirname(path.dirname(file))
  local state = wm.read_state(fs, dir)
  if not state then return nil end
  return { proj = proj, dir = dir, file = file, state = state }
end

local function publications_dir(band, band_folder, state)
  local lib = bandfile.library(band, state.song.library)
  return cycles.dir(band, band_folder, "publications", state.song.library, lib and lib.kind == "dated" and state.song.cycle or nil) .. "/" .. state.song.slug
end

local function display_time(iso) return (iso or ""):sub(1, 16):gsub("T", " ") end

-- proposal_status(fs, band, band_folder, ws) -> { id =, sent = "2026-09-29 21:40", status = "pending" | "accepted" } | nil
function M.proposal_status(fs, band, band_folder, ws)
  local last = deliveries.latest(fs, wm.outbox_dir(ws.dir))
  if not last then return nil end
  local info = deliveries.read(fs, last.dir)
  local status = deliveries.status(fs, publications_dir(band, band_folder, ws.state), last.id)
  return { id = last.id, sent = display_time(info and info.created), status = status }
end

-- status(fs, band, band_folder, ws) -> { sync =, latest =, base =, dirty =, closed =, proposal = }
function M.status(fs, band, band_folder, ws)
  local pub_dir = publications_dir(band, band_folder, ws.state)
  local latest = songs_list.latest_usable(fs, pub_dir)
  local newest = revisions.latest(fs, pub_dir)
  local fingerprint = workspace.fingerprint(ws.proj, band, ws.state.member)
  return {
    sync = wm.sync_state(latest and latest.number, ws.state, fingerprint),
    latest = latest and latest.number, base = ws.state.base_revision,
    -- a newer finished publication exists but its files have not all arrived yet
    arriving = newest ~= nil and newest.number > ws.state.base_revision and (latest == nil or newest.number > latest.number),
    dirty = reaper.IsProjectDirty(ws.proj) ~= 0,
    closed = not cycles.check_open(fs, band, band_folder, ws.state.song.library, ws.state.song.cycle),
    proposal = M.proposal_status(fs, band, band_folder, ws),
  }
end

------------------------------------------------------------------------------------ get the master

local function remove_stems(proj)
  local spans = folders.top_level(pm.depths(proj))
  for k = #spans, 1, -1 do
    local f = spans[k]
    if pm.get_marker(reaper.GetTrack(proj, f.first - 1), pm.KEY_STEM) == "1" then
      for i = f.last, f.first, -1 do reaper.DeleteTrack(reaper.GetTrack(proj, i - 1)) end
    end
  end
  for i = reaper.CountTracks(proj) - 1, 0, -1 do
    local tr = reaper.GetTrack(proj, i)
    if pm.get_marker(tr, pm.KEY_STEM) == "reference" then reaper.DeleteTrack(tr) end
  end
end

local function backup_id(fs, dir, epoch)
  local base = os.date("!b%Y%m%dT%H%M%SZ", epoch)
  local taken = {}
  for _, e in ipairs(fs.list(dir) or {}) do taken[e.name] = true end
  if not taken[base] then return base end
  local n = 2
  while taken[base .. "-" .. n] do n = n + 1 end
  return base .. "-" .. n
end

-- fetch(fs, band, band_folder, ws [, opts]) -> { from =, to =, structure =, backup = } | nil, code, detail
--   opts.yield, opts.epoch (tests), opts.now
-- Codes: project_unsaved, nothing_newer, the manifest problem codes, fetch_failed
-- The member's own folders are never touched; the workspace as it was is saved first (see undo_fetch).
function M.fetch(fs, band, band_folder, ws, opts)
  opts = opts or {}
  local proj, state = ws.proj, ws.state
  if reaper.IsProjectDirty(proj) ~= 0 then return nil, "project_unsaved" end
  -- the newest FINISHED revision decides; if its files have not all arrived, that is reported
  -- (a member should hear "still arriving", not "nothing new")
  local latest = revisions.latest(fs, publications_dir(band, band_folder, state))
  if not latest or latest.number <= state.base_revision then return nil, "nothing_newer" end
  local ok, problems = manifest.verify(fs, latest.dir, { yield = opts.yield })
  if not ok then return nil, problems[1].code, problems[1].path end
  local info = json.try_decode(fs.read_all(latest.dir .. "/publication.json") or "")
  local new_timing = json.try_decode(fs.read_all(latest.dir .. "/timing.json") or "")
  if type(info) ~= "table" or type(new_timing) ~= "table" then return nil, "bad_manifest", "publication.json" end

  -- 1. back up the workspace as it is (project file and state); media stays where it is
  local epoch = opts.epoch or os.time()
  local id = backup_id(fs, wm.backups_dir(ws.dir), epoch)
  local bdir = wm.backups_dir(ws.dir) .. "/" .. id
  local now = opts.now or changelog.now(epoch)
  if not fs.mkdirs(bdir) then return nil, "fetch_failed", bdir end
  local slug = state.song.slug
  local saved = fs.write_all(bdir .. "/" .. slug .. ".rpp", fs.read_all(ws.file) or "")
    and fs.write_all(bdir .. "/" .. wm.STATE_FILE, fs.read_all(wm.work_dir(ws.dir) .. "/" .. wm.STATE_FILE) or "")
    and fs.write_all(bdir .. "/fetch.json", json.encode({ from = state.base_revision, to = latest.number, created = now.iso }, { pretty = true }) .. "\n")
  if not saved then return nil, "fetch_failed", bdir end

  -- 2. the new stems and reference mix, in a folder of their own (older ones stay for undo)
  local mine = {}
  for _, r in ipairs(bandfile.roles_of(band, state.member)) do mine[r.id] = true end
  local stems = wm.work_dir(ws.dir) .. "/stems/r" .. latest.number
  if not fs.mkdirs(stems) then return nil, "fetch_failed", stems end
  local specs = {}
  for i, role in ipairs(info.roles) do
    if not mine[role.id] then
      local target = stems .. "/" .. role.id .. ".wav"
      local copied, err = copytree.copy_file(fs, latest.dir .. "/" .. role.stem, target, opts.yield)
      if not copied then return nil, "fetch_failed", tostring(err) end
      local owner_name = ""
      for _, m in ipairs(band.members) do if m.id == role.owner then owner_name = m.name end end
      local template = require("bandcollab.template")
      specs[role.id] = { role = role.id, owner = role.owner, file = target,
        color = template.PALETTE[(i - 1) % #template.PALETTE + 1], name = owner_name ~= "" and (role.label .. " - " .. owner_name) or role.label }
    end
  end
  local reference = stems .. "/reference.wav"
  local copied, err = copytree.copy_file(fs, latest.dir .. "/" .. info.reference, reference, opts.yield)
  if not copied then return nil, "fetch_failed", tostring(err) end

  -- 3. change the project; if anything goes wrong, load the saved file again (nothing was saved yet)
  local original = (reaper.EnumProjects(-1))
  reaper.SelectProjectInstance(proj)
  local own_tracks = {}
  for _, f in ipairs(pm.owned_folders(proj, band, state.member)) do
    for i = f.index, f.last do
      local track = reaper.GetTrack(proj, i - 1)
      local _, chunk = reaper.GetTrackStateChunk(track, "", false)
      own_tracks[#own_tracks + 1] = { track = track, chunk = chunk }
    end
  end
  local worked, failure = pcall(function()
    remove_stems(proj)
    local placed = {}
    for _, role in ipairs(info.roles) do
      local index = 0
      for j = #placed, 1, -1 do -- after the nearest earlier role that is in the project
        for _, f in ipairs(pm.role_folders(proj)) do if f.role == placed[j] then index = f.last end end
        if index > 0 then break end
      end
      if specs[role.id] then workspace.add_stem_group(proj, specs[role.id], index) end
      placed[#placed + 1] = role.id
    end
    local n = reaper.CountTracks(proj)
    reaper.InsertTrackAtIndex(n, false)
    local ref_track = reaper.GetTrack(proj, n)
    local ref_name = opts.reference_name or "Reference mix"
    reaper.GetSetMediaTrackInfo_String(ref_track, "P_NAME", ref_name, true)
    workspace.add_locked_item(ref_track, reference, ref_name)
    reaper.SetMediaTrackInfo_Value(ref_track, "B_MUTE", 1)
    pm.set_marker(ref_track, pm.KEY_STEM, "reference")
    workspace.apply_timing(proj, new_timing)
    -- a tempo change moves items that follow the tempo; the member's own work must stay exactly
    -- where they left it, so their tracks are put back as they were
    for _, own in ipairs(own_tracks) do reaper.SetTrackStateChunk(own.track, own.chunk, false) end
    pm.set_project_marker(proj, pm.KEY_BASE, tostring(latest.number))
    projects.save_bound(proj)
  end)
  if not worked then
    reaper.Main_openProject("noprompt:" .. ws.file)
    ws.proj = (reaper.EnumProjects(-1))
    return nil, "fetch_failed", tostring(failure)
  end
  projects.restore_selection(original)

  local structure = timing.compare(state.base_timing, new_timing)
  local from = state.base_revision
  state.base_revision, state.base_timing = latest.number, new_timing
  local wrote, werr = wm.write_state(fs, ws.dir, state)
  if not wrote then return nil, "fetch_failed", tostring(werr) end
  return { from = from, to = latest.number, structure = structure, backup = id }
end

-- can_undo(fs, ws) -> revision that would be restored | nil: is there a fetch that can still be undone?
function M.can_undo(fs, ws)
  local dir = wm.backups_dir(ws.dir)
  local from
  for _, e in ipairs(fs.list(dir) or {}) do
    if e.is_dir and e.name:match("^b%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ") then
      local info = json.try_decode(fs.read_all(dir .. "/" .. e.name .. "/fetch.json") or "")
      if type(info) == "table" and not info.undone then from = info.from end
    end
  end
  return from
end

-- undo_fetch(fs, ws) -> { restored = revision, proj = } | nil, code
-- Puts the workspace back as it was before the most recent fetch that has not been undone.
-- Anything done in the workspace since that fetch is discarded, as the saved copy is loaded again.
function M.undo_fetch(fs, ws)
  local dir = wm.backups_dir(ws.dir)
  local latest
  for _, e in ipairs(fs.list(dir) or {}) do
    if e.is_dir and e.name:match("^b%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ") then
      local info = json.try_decode(fs.read_all(dir .. "/" .. e.name .. "/fetch.json") or "")
      if type(info) == "table" and not info.undone then latest = { id = e.name, dir = dir .. "/" .. e.name, info = info } end
    end
  end
  if not latest then return nil, "nothing_to_undo" end
  local slug = ws.state.song.slug
  local project_copy = fs.read_all(latest.dir .. "/" .. slug .. ".rpp")
  local state_copy = fs.read_all(latest.dir .. "/" .. wm.STATE_FILE)
  if not project_copy or not state_copy then return nil, "nothing_to_undo" end
  local ok = fs.write_all(ws.file, project_copy) and fs.write_all(wm.work_dir(ws.dir) .. "/" .. wm.STATE_FILE, state_copy)
  if not ok then return nil, "fetch_failed", ws.file end
  latest.info.undone = true
  fs.write_all(latest.dir .. "/fetch.json", json.encode(latest.info, { pretty = true }) .. "\n")
  reaper.SelectProjectInstance(ws.proj)
  reaper.Main_openProject("noprompt:" .. ws.file) -- loads the saved copy into the same tab
  local proj = (reaper.EnumProjects(-1))
  ws.proj, ws.state = proj, wm.read_state(fs, ws.dir)
  return { restored = latest.info.from, proj = proj }
end

------------------------------------------------------------------------------------ sending

-- find_orphans(proj) -> list of { first =, last = } (1-based): top-level tracks or folders that
-- belong to no role and are not the reference mix. They would be lost in a proposal.
function M.find_orphans(proj)
  local depths = pm.depths(proj)
  local out, i = {}, 1
  while i <= #depths do
    local last = folders.span(depths, i) -- i itself for an ordinary track
    local track = reaper.GetTrack(proj, i - 1)
    if not pm.get_marker(track, pm.KEY_ROLE) and pm.get_marker(track, pm.KEY_STEM) ~= "reference" then
      out[#out + 1] = { first = i, last = last }
    end
    i = last + 1
  end
  return out
end

-- fix_orphans(proj, band, member_id) -> number of tracks moved | nil, "no_own_folder"
-- Moves stray tracks (with their items and any folder structure of their own) to the end of the
-- member's first folder. Nothing is dropped.
function M.fix_orphans(proj, band, member_id)
  local groups = M.find_orphans(proj)
  if #groups == 0 then return 0 end
  if #pm.owned_folders(proj, band, member_id) == 0 then return nil, "no_own_folder" end

  local moved = {}
  for _, g in ipairs(groups) do
    for i = g.first, g.last do
      local track = reaper.GetTrack(proj, i - 1)
      local _, chunk = reaper.GetTrackStateChunk(track, "", false)
      moved[#moved + 1] = { chunk = chunk, depth = math.floor(reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")) }
    end
  end
  for gi = #groups, 1, -1 do
    for i = groups[gi].last, groups[gi].first, -1 do reaper.DeleteTrack(reaper.GetTrack(proj, i - 1)) end
  end

  -- the member's folder may have moved up; the tracks go after its current last child. That child
  -- no longer closes the folder (one closing less), and the last moved track closes it instead.
  local target = pm.owned_folders(proj, band, member_id)[1]
  local old_last = reaper.GetTrack(proj, target.last - 1)
  reaper.SetMediaTrackInfo_Value(old_last, "I_FOLDERDEPTH", reaper.GetMediaTrackInfo_Value(old_last, "I_FOLDERDEPTH") + 1)
  for k, item in ipairs(moved) do
    local index = target.last + k - 1
    reaper.InsertTrackAtIndex(index, false)
    local track = reaper.GetTrack(proj, index)
    reaper.SetTrackStateChunk(track, item.chunk, false)
    reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", k == #moved and item.depth - 1 or item.depth)
  end
  return #moved
end

-- preflight(fs, band, band_folder, ws) -> { problems =, blocking = bool, warnings = { codes... } }
-- Each problem: { code =, severity = "blocking" | "warning" | "info", detail =, fix = "move_orphans" | nil }
--   blocking: must be fixed; warning: must be confirmed (or fixed); info: only told to the member
function M.preflight(fs, band, band_folder, ws)
  local proj, state = ws.proj, ws.state
  local problems = {}
  local function add(code, severity, detail, fix)
    problems[#problems + 1] = { code = code, severity = severity, detail = detail, fix = fix }
  end

  if reaper.IsProjectDirty(proj) ~= 0 then add("project_unsaved", "blocking") end
  if not cycles.check_open(fs, band, band_folder, state.song.library, state.song.cycle) then
    add("cycle_closed", "blocking", state.song.cycle)
  end

  local orphans = 0
  for _, g in ipairs(M.find_orphans(proj)) do orphans = orphans + (g.last - g.first + 1) end
  if orphans > 0 then add("send_orphans", "blocking", orphans, "move_orphans") end

  local items = 0
  for _, f in ipairs(pm.owned_folders(proj, band, state.member)) do
    for i = f.index, f.last do items = items + reaper.CountTrackMediaItems(reaper.GetTrack(proj, i - 1)) end
  end
  if items == 0 then add("send_empty", "warning") end

  for _, reason in ipairs(timing.compare(state.base_timing, publisher.capture_timing(proj)).reasons) do
    if reason == "tempo" then add("send_timing", "warning") end -- the length may differ: the member's takes can run longer
  end

  local fingerprint = workspace.fingerprint(proj, band, state.member)
  if fingerprint == (state.sent_fingerprint or state.own_fingerprint) then add("send_unchanged", "warning") end

  local outside = 0
  for _, text in ipairs(workspace.own_chunks(proj, band, state.member)) do
    for _, ref in ipairs(rpp.media_refs(text)) do
      if not path.relative(wm.work_dir(ws.dir), inspect.resolve(wm.work_dir(ws.dir), ref)) then outside = outside + 1 end
    end
  end
  if outside > 0 then add("send_media_outside", "info", outside) end

  local result = { problems = problems, blocking = false, warnings = {} }
  for _, p in ipairs(problems) do
    if p.severity == "blocking" then result.blocking = true end
    if p.severity == "warning" then result.warnings[#result.warnings + 1] = p.code end
  end
  return result
end

-- send(fs, band, band_folder, ws [, opts]) -> { id =, dir =, problems = } | nil, code, preflight
--   opts.note = { summary =, body = }; opts.acknowledged = { send_empty = true, ... } confirms warnings;
--   opts.epoch, opts.now, opts.yield (tests and progress)
-- The delivery is a complete, frozen folder in the outbox: the member's own folders as tracks plus
-- media (audio from outside the workspace is copied in), a manifest, and the completion marker last.
-- Codes: preflight_failed, preflight_needs_ack, publish_cannot_write
function M.send(fs, band, band_folder, ws, opts)
  opts = opts or {}
  local proj, state = ws.proj, ws.state
  local pre = M.preflight(fs, band, band_folder, ws)
  if pre.blocking then return nil, "preflight_failed", pre end
  for _, code in ipairs(pre.warnings) do
    if not (opts.acknowledged or {})[code] then return nil, "preflight_needs_ack", pre end
  end

  local epoch = opts.epoch or os.time()
  local now = opts.now or changelog.now(epoch)
  local outbox = wm.outbox_dir(ws.dir)
  local id = deliveries.unique_id(fs, outbox, epoch)
  local dir = outbox .. "/" .. id
  local roles = {}
  for _, f in ipairs(pm.owned_folders(proj, band, state.member)) do
    local n, err = ownexport.export(fs, proj, f, dir .. "/own/" .. f.role, wm.work_dir(ws.dir), opts.yield)
    if not n then return nil, "publish_cannot_write", tostring(err) end
    roles[#roles + 1] = f.role
  end

  local fingerprint = workspace.fingerprint(proj, band, state.member)
  local info = {
    schema = deliveries.SCHEMA, song = state.song, member = state.member, base_revision = state.base_revision,
    created = now.iso, note = opts.note, roles = roles, fingerprint = fingerprint,
  }
  if not fs.write_all(dir .. "/" .. deliveries.INFO, json.encode(info, { pretty = true }) .. "\n") then
    return nil, "publish_cannot_write", dir
  end
  local built = manifest.build(fs, dir, { kind = "delivery", created = now.iso, meta = { member = state.member, delivery = id }, yield = opts.yield })
  local wrote, werr = manifest.write(fs, dir, built) -- the completion marker comes last
  if not wrote then return nil, "publish_cannot_write", tostring(werr) end

  state.sent_fingerprint = fingerprint
  wm.write_state(fs, ws.dir, state)
  return { id = id, dir = dir, problems = pre.problems }
end

return M
