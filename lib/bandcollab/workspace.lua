-- The member's own workspace in REAPER (needs the REAPER API): create it from a publication, look
-- at its state. Their own role folders are real, editable tracks; everyone else's work is a
-- collapsed stem folder whose items are locked, so nothing can be moved out of line by accident
-- (the folder faders stay free, so members can balance what they hear).
local pm = require("bandcollab.projectmodel")
local projects = require("bandcollab.projects")
local wm = require("bandcollab.workspace_model")
local revisions = require("bandcollab.revisions")
local manifest = require("bandcollab.manifest")
local cycles = require("bandcollab.cycles")
local bandfile = require("bandcollab.bandfile")
local copytree = require("bandcollab.copytree")
local chunks = require("bandcollab.chunks")
local template = require("bandcollab.template")
local changelog = require("bandcollab.changelog")
local rpp = require("bandcollab.rpp")
local path = require("bandcollab.path")
local json = require("bandcollab.json")

local M = {}

local EMPTY_PROJECT = '<REAPER_PROJECT 0.1 "7.0" 0\n>\n'

local function native(color) return reaper.ColorToNative(color[1], color[2], color[3]) | 0x1000000 end

-- apply_timing(proj, timing): make the project's tempo map and section markers those of a
-- publication (the stems were rendered against them).
function M.apply_timing(proj, timing)
  for i = reaper.CountTempoTimeSigMarkers(proj) - 1, 0, -1 do reaper.DeleteTempoTimeSigMarker(proj, i) end
  reaper.SetCurrentBPM(proj, timing.bpm, false)
  if timing.beats_per_measure and timing.beats_per_measure ~= 4 then
    reaper.SetTempoTimeSigMarker(proj, -1, 0, -1, -1, timing.bpm, timing.beats_per_measure, 4, false)
  end
  for _, entry in ipairs(timing.tempo_map or {}) do
    reaper.SetTempoTimeSigMarker(proj, -1, entry.pos, -1, -1, entry.bpm, entry.num or 0, entry.den or 0, entry.linear or false)
  end
  local i = reaper.CountProjectMarkers(proj) - 1
  while i >= 0 do reaper.DeleteProjectMarkerByIndex(proj, i); i = i - 1 end
  for _, m in ipairs(timing.markers or {}) do
    reaper.AddProjectMarker2(proj, m.region and true or false, m.pos, m.rgnend or 0, m.name or "", -1, 0)
  end
end

-- add_locked_item(track, file, name): puts a whole audio file on the track at 0 and locks the item
local function add_locked_item(track, file, name)
  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  local source = reaper.PCM_Source_CreateFromFile(file)
  reaper.SetMediaItemTake_Source(take, source)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", (reaper.GetMediaSourceLength(source)))
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
  reaper.SetMediaItemInfo_Value(item, "C_BEATATTACHMODE", 0) -- absolute time: a tempo change must never stretch someone else's recording
  reaper.SetMediaItemInfo_Value(item, "C_LOCK", 1)
  return item
end

-- add_stem_group(proj, spec [, index]): a collapsed folder with one track holding the stem, items
-- locked. It goes at the 0-based track `index` (default: the end of the project).
--   spec = { name =, role =, owner =, file =, color = {r,g,b} }
local function add_stem_group(proj, spec, index)
  local n = index or reaper.CountTracks(proj)
  reaper.InsertTrackAtIndex(n, false)
  reaper.InsertTrackAtIndex(n + 1, false)
  local folder, child = reaper.GetTrack(proj, n), reaper.GetTrack(proj, n + 1)
  reaper.GetSetMediaTrackInfo_String(folder, "P_NAME", spec.name, true)
  reaper.GetSetMediaTrackInfo_String(child, "P_NAME", spec.name, true)
  reaper.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)
  reaper.SetMediaTrackInfo_Value(child, "I_FOLDERDEPTH", -1)
  reaper.SetMediaTrackInfo_Value(folder, "I_CUSTOMCOLOR", native(spec.color))
  reaper.SetMediaTrackInfo_Value(child, "I_CUSTOMCOLOR", native(spec.color))
  pm.set_marker(folder, pm.KEY_ROLE, spec.role)
  if spec.owner then pm.set_marker(folder, pm.KEY_OWNER, spec.owner) end
  pm.set_marker(folder, pm.KEY_STEM, "1")
  add_locked_item(child, spec.file, spec.name)
  reaper.SetMediaTrackInfo_Value(folder, "I_FOLDERCOMPACT", 2) -- fully collapsed
  return folder
end

-- own_chunks(proj, band, member_id) -> the member's own role folders as chunk texts, in project order
M.add_stem_group = add_stem_group
M.add_locked_item = add_locked_item

function M.own_chunks(proj, band, member_id)
  local out = {}
  for _, f in ipairs(pm.owned_folders(proj, band, member_id)) do
    local parts = {}
    for i = f.index, f.last do
      local _, chunk = reaper.GetTrackStateChunk(reaper.GetTrack(proj, i - 1), "", false)
      parts[#parts + 1] = chunk
    end
    out[#out + 1] = table.concat(parts, "\n")
  end
  return out
end

function M.fingerprint(proj, band, member_id) return wm.fingerprint(M.own_chunks(proj, band, member_id)) end

-- create(fs, band, band_folder, member_id, song [, opts]) -> workspace | nil, code, detail
--   song: an entry from songs_list (library, cycle, slug, dir, title, id, latest)
--   opts.yield(bytes, file) is called while files are copied; opts.now is a changelog.now() value;
--   opts.keep_open = false closes the workspace again (default: it stays open)
-- Codes: cycle_closed, workspace_exists, the manifest problem codes, publish_cannot_write
function M.create(fs, band, band_folder, member_id, song, opts)
  opts = opts or {}
  local open, code, detail = cycles.check_open(fs, band, band_folder, song.library, song.cycle)
  if not open then return nil, code, detail end
  local dir = wm.dir(band, band_folder, member_id, song)
  if wm.read_state(fs, dir) then return nil, "workspace_exists", dir end

  local rev = revisions.dir(song.dir, song.latest)
  local ok, problems = manifest.verify(fs, rev, { yield = opts.yield })
  if not ok then return nil, problems[1].code, problems[1].path end
  local info = json.try_decode(fs.read_all(rev .. "/publication.json") or "")
  local timing_record = json.try_decode(fs.read_all(rev .. "/timing.json") or "")
  if type(info) ~= "table" or type(timing_record) ~= "table" then return nil, "bad_manifest", "publication.json" end

  local mine = {}
  for _, r in ipairs(bandfile.roles_of(band, member_id)) do mine[r.id] = true end
  local work = wm.work_dir(dir)
  local stems = work .. "/stems/r" .. song.latest
  if not (fs.mkdirs(work .. "/media") and fs.mkdirs(stems)) then return nil, "publish_cannot_write", work end

  local plan = {}
  for i, role in ipairs(info.roles) do
    local color = template.PALETTE[(i - 1) % #template.PALETTE + 1]
    if mine[role.id] then
      local text = fs.read_all(rev .. "/" .. role.own .. "/tracks.chunk") or ""
      local map = {}
      for _, ref in ipairs(rpp.media_refs(text)) do
        local target = "media/" .. role.id .. "/" .. path.basename(ref)
        if not fs.mkdirs(work .. "/media/" .. role.id) then return nil, "publish_cannot_write", work .. "/media/" .. role.id end
        local copied, err = copytree.copy_file(fs, rev .. "/" .. role.own .. "/" .. ref, work .. "/" .. target, opts.yield)
        if not copied then return nil, "publish_cannot_write", tostring(err) end
        map[ref] = target
      end
      plan[#plan + 1] = { own = true, role = role.id, chunks = chunks.split(rpp.rewrite_media(text, map)) }
    else
      local target = stems .. "/" .. role.id .. ".wav"
      local copied, err = copytree.copy_file(fs, rev .. "/" .. role.stem, target, opts.yield)
      if not copied then return nil, "publish_cannot_write", tostring(err) end
      local owner_name = ""
      for _, m in ipairs(band.members) do if m.id == role.owner then owner_name = m.name end end
      plan[#plan + 1] = {
        own = false, role = role.id, owner = role.owner, file = target, color = color,
        name = owner_name ~= "" and (role.label .. " - " .. owner_name) or role.label,
      }
    end
  end
  local reference = stems .. "/reference.wav"
  local copied, err = copytree.copy_file(fs, rev .. "/" .. info.reference, reference, opts.yield)
  if not copied then return nil, "publish_cannot_write", tostring(err) end

  -- the project: written empty, then OPENED from its own file, and only then filled in
  local file = wm.project_file(dir, song.slug)
  if not fs.write_all(file, EMPTY_PROJECT) then return nil, "publish_cannot_write", file end
  local original = (reaper.EnumProjects(-1))
  local proj = projects.open_bound(file)
  M.apply_timing(proj, timing_record)
  for _, item in ipairs(plan) do
    if item.own then
      for _, chunk in ipairs(item.chunks) do
        local index = reaper.CountTracks(proj)
        reaper.InsertTrackAtIndex(index, false)
        reaper.SetTrackStateChunk(reaper.GetTrack(proj, index), chunk, false)
      end
    else
      add_stem_group(proj, item)
    end
  end
  local n = reaper.CountTracks(proj)
  reaper.InsertTrackAtIndex(n, false)
  local ref_track = reaper.GetTrack(proj, n)
  local ref_name = (opts.reference_name or "Reference mix")
  reaper.GetSetMediaTrackInfo_String(ref_track, "P_NAME", ref_name, true)
  add_locked_item(ref_track, reference, ref_name)
  reaper.SetMediaTrackInfo_Value(ref_track, "B_MUTE", 1)
  pm.set_marker(ref_track, pm.KEY_STEM, "reference")

  pm.set_recording_path(proj)
  pm.set_project_marker(proj, pm.KEY_KIND, "workspace")
  pm.set_project_marker(proj, pm.KEY_BAND, band.name)
  pm.set_project_marker(proj, pm.KEY_SONG, info.song.id)
  pm.set_project_marker(proj, pm.KEY_MEMBER, member_id)
  pm.set_project_marker(proj, pm.KEY_BASE, tostring(song.latest))
  reaper.GetSetProjectInfo_String(proj, "PROJECT_TITLE", info.song.title, true)
  projects.save_bound(proj)

  local now = opts.now or changelog.now()
  local state = {
    song = { id = info.song.id, title = info.song.title, slug = song.slug, library = song.library, cycle = song.cycle },
    member = member_id, base_revision = song.latest, own_fingerprint = M.fingerprint(proj, band, member_id),
    created = now.iso, base_timing = timing_record,
  }
  local wrote, werr = wm.write_state(fs, dir, state)
  if not wrote then return nil, "publish_cannot_write", tostring(werr) end
  if opts.keep_open == false then
    projects.close_tab(proj)
    projects.restore_selection(original)
  end
  return { proj = proj, dir = dir, file = file, state = state }
end

return M
