-- The producer's import: taking a member's proposal into the master (needs the REAPER API).
-- Only the producer's tool ever writes the master. A proposal is checked first, the master is
-- backed up before anything is written, only the proposer's OWN role folders are replaced (anything
-- else a delivery contains is ignored), the result is logged, and the import can be undone.
local pm = require("bandcollab.projectmodel")
local projects = require("bandcollab.projects")
local publisher = require("bandcollab.publisher")
local songfile = require("bandcollab.songfile")
local deliveries = require("bandcollab.deliveries")
local revisions = require("bandcollab.revisions")
local cycles = require("bandcollab.cycles")
local manifest = require("bandcollab.manifest")
local changelog = require("bandcollab.changelog")
local copytree = require("bandcollab.copytree")
local timing = require("bandcollab.timing")
local bandfile = require("bandcollab.bandfile")
local wm = require("bandcollab.workspace_model")
local chunks = require("bandcollab.chunks")
local rpp = require("bandcollab.rpp")
local json = require("bandcollab.json")
local path = require("bandcollab.path")

local M = {}

-- identify_master(fs, proj) -> master | nil: is this open project a registered song's master?
function M.identify_master(fs, proj)
  local file = publisher.project_file(proj)
  if not file then return nil end
  local dir = path.dirname(file)
  local song = songfile.read(fs, dir)
  if not song then return nil end
  return { proj = proj, file = file, dir = dir, song = song }
end

-- publications_dir(band, band_folder, master) -> the song's folder in the publications area
function M.publications_dir(band, band_folder, master)
  local lib = bandfile.library(band, master.song.library)
  return cycles.dir(band, band_folder, "publications", master.song.library, lib and lib.kind == "dated" and master.song.cycle or nil) .. "/" .. master.song.slug
end

local function count_items(text)
  local n = 0
  for line in text:gmatch("[^\r\n]+") do if line:match("^%s*<ITEM") then n = n + 1 end end
  return n
end

local function folder_counts(proj, folder)
  local items = 0
  for i = folder.index, folder.last do items = items + reaper.CountTrackMediaItems(reaper.GetTrack(proj, i - 1)) end
  return { tracks = folder.last - folder.index + 1, items = items }
end

local function seconds_text(s) return changelog.clock(s) end

-- preview(fs, band, band_folder, master, entry) -> preview | nil, code, detail
--   entry: a row of the inbox. Nothing is written. The integrity of the delivery is checked first.
-- preview = { info =, member =, folders = { {role, label, ignored, missing, conflict, before, after} },
--             warnings = { {code, severity, detail} }, base =, current =, timing = {...} }
function M.preview(fs, band, band_folder, master, entry)
  local ok, problems = manifest.verify(fs, entry.dir)
  if not ok then return nil, problems[1].code, problems[1].path end
  local info = deliveries.read(fs, entry.dir)
  if not info then return nil, "bad_manifest", deliveries.INFO end
  if info.song and info.song.id ~= master.song.id then return nil, "wrong_song" end

  local owned = {}
  for _, r in ipairs(bandfile.roles_of(band, entry.member)) do owned[r.id] = r end
  local base_info
  local base_text = fs.read_all(entry.pub_dir .. "/r" .. tostring(info.base_revision) .. "/publication.json")
  if base_text then base_info = json.try_decode(base_text) end

  local warnings = {}
  local function warn(code, severity, detail, vars) warnings[#warnings + 1] = { code = code, severity = severity, detail = detail, vars = vars } end
  local result_folders, importable = {}, 0
  local master_folders = {}
  for _, f in ipairs(pm.role_folders(master.proj)) do master_folders[f.role] = f end

  for _, role_id in ipairs(info.roles or {}) do
    local label = owned[role_id] and owned[role_id].label or role_id
    local row = { role = role_id, label = label }
    if not owned[role_id] then
      row.ignored = true
      warn("import_ignored_role", "info", role_id)
    else
      importable = importable + 1
      local text = fs.read_all(entry.dir .. "/own/" .. role_id .. "/tracks.chunk") or ""
      row.after = { tracks = #chunks.split(text), items = count_items(text) }
      local current = master_folders[role_id]
      if current then
        row.before = folder_counts(master.proj, current)
        -- did the producer change this folder after the version the member worked on?
        local published
        for _, r in ipairs(base_info and base_info.roles or {}) do if r.id == role_id then published = r.fingerprint end end
        if published and published ~= wm.fingerprint({ pm.folder_chunk(master.proj, current) }) then
          row.conflict = true
          warn("import_conflict", "warning", label)
        end
      else
        row.missing = true
        warn("import_folder_missing", "warning", label)
      end
    end
    result_folders[#result_folders + 1] = row
  end
  if importable == 0 then return nil, "nothing_to_import" end

  local latest = revisions.latest(fs, entry.pub_dir)
  if latest and info.base_revision and info.base_revision < latest.number then
    warn("import_outdated", "warning", nil, { base = info.base_revision, current = latest.number })
  end
  local master_timing = publisher.capture_timing(master.proj)
  local compared = info.timing and timing.compare(master_timing, info.timing) or { reasons = {} }
  local tempo_differs = false
  for _, r in ipairs(compared.reasons) do if r == "tempo" then tempo_differs = true end end
  if tempo_differs then warn("import_tempo", "warning") end
  if info.timing and info.timing.length and info.timing.length > master_timing.length + timing.TOLERANCE then
    warn("import_longer", "info", seconds_text(info.timing.length) .. " / " .. seconds_text(master_timing.length))
  end

  return {
    info = info, member = entry.member, folders = result_folders, warnings = warnings,
    base = info.base_revision, current = latest and latest.number or nil, note = info.note,
    timing = { master = master_timing, proposal = info.timing, tempo_differs = tempo_differs },
  }
end

local function backup_id(fs, dir, epoch)
  local base = os.date("!i%Y%m%dT%H%M%SZ", epoch)
  local taken = {}
  for _, e in ipairs(fs.list(dir) or {}) do taken[e.name] = true end
  if not taken[base] then return base end
  local n = 2
  while taken[base .. "-" .. n] do n = n + 1 end
  return base .. "-" .. n
end

local function title_of(master) return master.song.title or master.song.slug end

-- import(fs, band, band_folder, master, entry, S [, opts]) -> result | nil, code, detail
--   opts.note = { summary =, body = } overrides the member's note in the log (the producer may edit it)
--   opts.yield, opts.epoch, opts.now
-- result = { delivery =, backup =, replaced = { {role =, label =, tracks =}, ... } }
-- Codes: project_unsaved, already_imported, wrong_song, nothing_to_import, the manifest problem codes,
--        import_backup_failed, import_failed
function M.import(fs, band, band_folder, master, entry, S, opts)
  opts = opts or {}
  local proj = master.proj
  if reaper.IsProjectDirty(proj) ~= 0 then return nil, "project_unsaved" end
  if deliveries.status(fs, entry.pub_dir, entry.delivery) == "accepted" then return nil, "already_imported" end
  local pre, code, detail = M.preview(fs, band, band_folder, master, entry)
  if not pre then return nil, code, detail end

  -- 1. the backup comes first: nothing else is written until it exists
  local epoch = opts.epoch or os.time()
  local now = opts.now or changelog.now(epoch)
  local id = backup_id(fs, master.dir .. "/backups", epoch)
  local bdir = master.dir .. "/backups/" .. id
  local copy = fs.read_all(master.file)
  local saved = copy and fs.mkdirs(bdir)
    and fs.write_all(bdir .. "/" .. path.basename(master.file), copy)
    and fs.write_all(bdir .. "/import.json", json.encode({ delivery = entry.delivery, member = entry.member, created = now.iso }, { pretty = true }) .. "\n")
  if not saved then return nil, "import_backup_failed", bdir end

  -- 2. the proposer's own folders: media into the master's media folder, tracks with rewritten paths
  local plan = {}
  for _, row in ipairs(pre.folders) do
    if not row.ignored then
      local text = fs.read_all(entry.dir .. "/own/" .. row.role .. "/tracks.chunk") or ""
      local map = {}
      for _, ref in ipairs(rpp.media_refs(text)) do
        local target = "media/" .. entry.delivery .. "/" .. row.role .. "/" .. path.basename(ref)
        if not fs.mkdirs(master.dir .. "/media/" .. entry.delivery .. "/" .. row.role) then return nil, "import_failed", target end
        local copied, err = copytree.copy_file(fs, entry.dir .. "/own/" .. row.role .. "/" .. ref, master.dir .. "/" .. target, opts.yield)
        if not copied then return nil, "import_failed", tostring(err) end
        map[ref] = target
      end
      plan[#plan + 1] = { role = row.role, label = row.label, chunks = chunks.split(rpp.rewrite_media(text, map)) }
    end
  end

  -- 3. replace the folders in the project; if anything fails the file on disk is loaded again
  local original = (reaper.EnumProjects(-1))
  reaper.SelectProjectInstance(proj)
  local replaced = {}
  local worked, failure = pcall(function()
    for _, item in ipairs(plan) do
      local index0
      local found
      for _, f in ipairs(pm.role_folders(proj)) do if f.role == item.role then found = f end end
      if found then
        index0 = found.index - 1
        for i = found.last, found.index, -1 do reaper.DeleteTrack(reaper.GetTrack(proj, i - 1)) end
      else
        index0 = reaper.CountTracks(proj)
      end
      for k, chunk in ipairs(item.chunks) do
        reaper.InsertTrackAtIndex(index0 + k - 1, false)
        reaper.SetTrackStateChunk(reaper.GetTrack(proj, index0 + k - 1), chunk, false)
      end
      local folder_track = reaper.GetTrack(proj, index0)
      pm.set_marker(folder_track, pm.KEY_ROLE, item.role)
      local owner = bandfile.owner_of(band, item.role)
      if owner then pm.set_marker(folder_track, pm.KEY_OWNER, owner.id) end
      replaced[#replaced + 1] = { role = item.role, label = item.label, tracks = #item.chunks }
    end
    projects.save_bound(proj)
  end)
  if not worked then
    reaper.Main_openProject("noprompt:" .. master.file)
    master.proj = (reaper.EnumProjects(-1))
    return nil, "import_failed", tostring(failure)
  end
  projects.restore_selection(original)

  -- 4. record it: what was taken in (members see it) and the log
  deliveries.record_import(fs, entry.pub_dir, { delivery = entry.delivery, member = entry.member, at = now.iso, backup = id })
  local facts = { { key = "sent", vars = { time = entry.sent } } }
  for _, r in ipairs(replaced) do facts[#facts + 1] = { key = "taken", vars = { n = r.tracks, role = r.label } } end
  changelog.add(fs, entry.pub_dir .. "/" .. changelog.file_name(S), title_of(master), {
    kind = "import", time = now, actor = entry.member_name, note = opts.note or pre.info.note, facts = facts,
  }, S)
  return { delivery = entry.delivery, backup = id, replaced = replaced }
end

local function latest_backup(fs, master)
  local dir = master.dir .. "/backups"
  local latest
  for _, e in ipairs(fs.list(dir) or {}) do
    if e.is_dir and e.name:match("^i%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ") then
      local info = json.try_decode(fs.read_all(dir .. "/" .. e.name .. "/import.json") or "")
      if type(info) == "table" and not info.undone then latest = { id = e.name, dir = dir .. "/" .. e.name, info = info } end
    end
  end
  return latest
end

-- can_undo(fs, master) -> delivery id of the import that "Kumoa" would reverse | nil
function M.can_undo(fs, master)
  local b = latest_backup(fs, master)
  return b and b.info.delivery or nil
end

-- undo_import(fs, band, band_folder, master, entry_pub_dir, S [, opts]) -> { delivery =, proj = } | nil, code
-- Restores the master from the backup made before the last import, makes that proposal pending
-- again, and records the reversal in the log. Whatever was done in the master since is lost.
function M.undo_import(fs, band, band_folder, master, pub_dir, S, opts)
  opts = opts or {}
  local b = latest_backup(fs, master)
  if not b then return nil, "nothing_to_undo_import" end
  local copy = fs.read_all(b.dir .. "/" .. path.basename(master.file))
  if not copy then return nil, "nothing_to_undo_import" end
  if not fs.write_all(master.file, copy) then return nil, "import_failed", master.file end
  b.info.undone = true
  fs.write_all(b.dir .. "/import.json", json.encode(b.info, { pretty = true }) .. "\n")
  deliveries.remove_import(fs, pub_dir, b.info.delivery)
  reaper.SelectProjectInstance(master.proj)
  reaper.Main_openProject("noprompt:" .. master.file) -- the saved copy goes back into the same tab
  master.proj = (reaper.EnumProjects(-1))
  local now = opts.now or changelog.now(opts.epoch)
  local actor
  for _, m in ipairs(band.members) do if m.id == band.producer then actor = m.name end end
  changelog.add(fs, pub_dir .. "/" .. changelog.file_name(S), title_of(master),
    { kind = "import_undone", time = now, actor = actor, note = { summary = b.info.delivery } }, S)
  return { delivery = b.info.delivery, proj = master.proj }
end

return M
