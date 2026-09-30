-- Publishes the open master project as a numbered revision (needs the REAPER API).
-- A publication holds, for every role folder, a stem rendered as the producer hears it (folder
-- processing included, master bus excluded), a reference mix with the master bus, the timing
-- information, and the folder's own tracks and media so a member can start a workspace from the
-- publication alone. The manifest and completion marker are written last.
local pm = require("bandcollab.projectmodel")
local songfile = require("bandcollab.songfile")
local cycles = require("bandcollab.cycles")
local revisions = require("bandcollab.revisions")
local timing = require("bandcollab.timing")
local manifest = require("bandcollab.manifest")
local copytree = require("bandcollab.copytree")
local changelog = require("bandcollab.changelog")
local inspect = require("bandcollab.inspect")
local bandfile = require("bandcollab.bandfile")
local slug = require("bandcollab.slug")
local rpp = require("bandcollab.rpp")
local json = require("bandcollab.json")
local path = require("bandcollab.path")

local M = {}

M.SCHEMA = 1
M.FORMAT_WAV24 = "ZXZhdxgAAQ==" -- REAPER's render format string for WAV, 24 bit
-- RENDER_SETTINGS values found in docs/spikes/stems.md
M.STEMS_ONLY = 3   -- stems of the selected tracks, no master bus
M.MASTER_MIX = 0   -- the master mix, master bus included

local NUMERIC = { "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_CHANNELS", "RENDER_SRATE", "RENDER_STARTPOS",
  "RENDER_ENDPOS", "RENDER_TAILFLAG", "RENDER_ADDTOPROJ", "RENDER_DITHER" }
local TEXT = { "RENDER_FILE", "RENDER_PATTERN", "RENDER_FORMAT" }

local function save_render_settings(proj)
  local saved = { numeric = {}, text = {} }
  for _, k in ipairs(NUMERIC) do saved.numeric[k] = reaper.GetSetProjectInfo(proj, k, 0, false) end
  for _, k in ipairs(TEXT) do local _, v = reaper.GetSetProjectInfo_String(proj, k, "", false); saved.text[k] = v end
  return saved
end

local function restore_render_settings(proj, saved)
  for k, v in pairs(saved.numeric) do reaper.GetSetProjectInfo(proj, k, v, true) end
  for k, v in pairs(saved.text) do reaper.GetSetProjectInfo_String(proj, k, v, true) end
end

local function selected_tracks(proj)
  local out = {}
  for i = 0, reaper.CountSelectedTracks(proj) - 1 do out[#out + 1] = reaper.GetSelectedTrack(proj, i) end
  return out
end

local function select_only(proj, tracks)
  for i = 0, reaper.CountTracks(proj) - 1 do reaper.SetTrackSelected(reaper.GetTrack(proj, i), false) end
  for _, tr in ipairs(tracks) do reaper.SetTrackSelected(tr, true) end
end

-- project_file(proj) -> path of the project's .rpp, or nil for an unsaved project
function M.project_file(proj)
  local i = 0
  while true do
    local p, file = reaper.EnumProjects(i, "")
    if not p then return nil end
    if p == proj then return file ~= "" and file or nil end
    i = i + 1
  end
end

-- capture_timing(proj) -> timing record (see timing.lua)
function M.capture_timing(proj)
  local bpm, bpi = reaper.GetProjectTimeSignature2(proj)
  local map = {}
  for i = 0, reaper.CountTempoTimeSigMarkers(proj) - 1 do
    local _, pos, _, _, tempo, num, den, linear = reaper.GetTempoTimeSigMarker(proj, i)
    map[#map + 1] = { pos = pos, bpm = tempo, num = num, den = den, linear = linear }
  end
  local markers = {}
  local i = 0
  while true do
    local ret, is_region, pos, region_end, name = reaper.EnumProjectMarkers2(proj, i)
    if not ret or ret == 0 then break end
    markers[#markers + 1] = { pos = pos, rgnend = is_region and region_end or nil, region = is_region or nil, name = name }
    i = i + 1
  end
  return timing.capture({
    length = reaper.GetProjectLength(proj), bpm = bpm, beats_per_measure = bpi,
    sample_rate = reaper.GetSetProjectInfo(proj, "PROJECT_SRATE", 0, false), tempo_map = map, markers = markers,
  })
end

-- Renders with the given RENDER_SETTINGS value into dir/<pattern>.wav; returns the file or nil, err.
local function render(fs, proj, dir, pattern, settings, sample_rate)
  if not fs.mkdirs(dir) then return nil, "cannot create " .. dir end
  reaper.GetSetProjectInfo_String(proj, "RENDER_FILE", dir, true)
  reaper.GetSetProjectInfo_String(proj, "RENDER_PATTERN", pattern, true)
  reaper.GetSetProjectInfo_String(proj, "RENDER_FORMAT", M.FORMAT_WAV24, true)
  reaper.GetSetProjectInfo(proj, "RENDER_SRATE", sample_rate, true)
  reaper.GetSetProjectInfo(proj, "RENDER_CHANNELS", 2, true)
  reaper.GetSetProjectInfo(proj, "RENDER_BOUNDSFLAG", 1, true) -- the entire project: every file is equally long
  reaper.GetSetProjectInfo(proj, "RENDER_TAILFLAG", 0, true)
  reaper.GetSetProjectInfo(proj, "RENDER_ADDTOPROJ", 0, true)
  reaper.GetSetProjectInfo(proj, "RENDER_SETTINGS", settings, true)
  reaper.SelectProjectInstance(proj)
  reaper.Main_OnCommand(42230, 0) -- render with the most recent settings, closing the dialog when done
  local file = dir .. "/" .. pattern .. ".wav"
  if not fs.exists(file) or (fs.size(file) or 0) == 0 then return nil, file end
  return file
end

-- export_own(fs, proj, folder, dir, project_dir, yield) -> number of media files | nil, err
-- Writes dir/tracks.chunk (the folder's track state) and dir/media/* with the files it uses, under
-- safe names, with the chunk's FILE lines pointing at them.
local function export_own(fs, proj, folder, dir, project_dir, yield)
  local chunks = {}
  for i = folder.index, folder.last do
    local _, chunk = reaper.GetTrackStateChunk(reaper.GetTrack(proj, i - 1), "", false)
    chunks[#chunks + 1] = chunk
  end
  local text = table.concat(chunks, "\n")
  local map, used, count = {}, {}, 0
  for _, ref in ipairs(rpp.media_refs(text)) do
    local source = inspect.resolve(project_dir, ref)
    local base, ext = path.basename(source):match("^(.*)(%.[^.]*)$")
    if not base then base, ext = path.basename(source), "" end
    local name = slug.unique(slug.slug(base), used) .. ext:lower()
    used[name:gsub("%.[^.]*$", "")] = true
    used[slug.slug(base)] = true
    if not fs.mkdirs(dir .. "/media") then return nil, "cannot create " .. dir .. "/media" end
    local ok, err = copytree.copy_file(fs, source, dir .. "/media/" .. name, yield)
    if not ok then return nil, "cannot copy " .. ref .. ": " .. tostring(err) end
    map[ref] = "media/" .. name
    count = count + 1
  end
  local written, werr = fs.write_all(dir .. "/tracks.chunk", rpp.rewrite_media(text, map))
  if not written then return nil, werr end
  return count
end

-- publish(fs, band, band_folder, proj, S [, opts]) -> result | nil, code, detail
--   opts.note = { summary =, body = }   opts.tasks = { {who =, text =}, ... }
--   opts.step(text)   called between the phases, for progress display
--   opts.yield        passed to file copying; opts.now = changelog.now() value (tests)
-- Codes: project_unsaved, not_a_song, unknown_library, no_role_folders, cycle_closed, render_failed,
--        publish_cannot_write
function M.publish(fs, band, band_folder, proj, S, opts)
  opts = opts or {}
  local function step(text) if opts.step then opts.step(text) end end

  local file = M.project_file(proj)
  if not file or reaper.IsProjectDirty(proj) ~= 0 then return nil, "project_unsaved" end
  local project_dir = path.dirname(file)
  local song = songfile.read(fs, project_dir)
  if not song then return nil, "not_a_song" end
  local library = bandfile.library(band, song.library)
  if not library then return nil, "unknown_library", song.library end
  local role_folders = pm.role_folders(proj)
  if #role_folders == 0 then return nil, "no_role_folders" end
  local open, code, detail = cycles.check_open(fs, band, band_folder, library.id, song.cycle)
  if not open then return nil, code, detail end

  local pub_dir = cycles.dir(band, band_folder, "publications", library.id, library.kind == "dated" and song.cycle or nil) .. "/" .. song.slug
  local number, rev_dir = revisions.next(fs, pub_dir)
  local writable, wcode = revisions.writable(fs, rev_dir)
  if not writable then return nil, "publish_cannot_write", wcode end

  local previous = revisions.latest(fs, pub_dir)
  local previous_timing
  if previous then
    local text = fs.read_all(previous.dir .. "/timing.json")
    previous_timing = text and json.try_decode(text)
  end

  local saved, selection = save_render_settings(proj), selected_tracks(proj)
  local sample_rate = math.floor(reaper.GetSetProjectInfo(proj, "PROJECT_SRATE", 0, false))
  if sample_rate <= 0 then sample_rate = 48000 end

  local roles = {}
  local failure_code, failure_detail
  for _, f in ipairs(role_folders) do
    step("stem: " .. f.role)
    select_only(proj, { f.track })
    local rendered, err = render(fs, proj, rev_dir .. "/stems", f.role, M.STEMS_ONLY, sample_rate)
    if not rendered then failure_code, failure_detail = "render_failed", err; break end
    local owner = bandfile.owner_of(band, f.role)
    local role_info
    for _, r in ipairs(band.roles) do if r.id == f.role then role_info = r end end
    roles[#roles + 1] = {
      id = f.role, label = role_info and role_info.label or f.role, owner = owner and owner.id or nil,
      stem = "stems/" .. f.role .. ".wav", own = "own/" .. f.role,
    }
    step("own: " .. f.role)
    local n, eerr = export_own(fs, proj, f, rev_dir .. "/own/" .. f.role, project_dir, opts.yield)
    if not n then failure_code, failure_detail = "publish_cannot_write", eerr; break end
  end

  if not failure_code then
    step("reference")
    select_only(proj, {})
    local rendered, err = render(fs, proj, rev_dir, "reference", M.MASTER_MIX, sample_rate)
    if not rendered then failure_code, failure_detail = "render_failed", err end
  end

  restore_render_settings(proj, saved)
  select_only(proj, selection)
  if failure_code then return nil, failure_code, failure_detail end

  step("timing")
  local current = M.capture_timing(proj)
  local structure = timing.compare(previous_timing, current)
  local now = opts.now or changelog.now()
  local info = {
    schema = M.SCHEMA,
    song = { id = song.id, title = song.title, slug = song.slug, library = library.id, cycle = song.cycle },
    revision = number, previous = previous and previous.number or nil, created = now.iso,
    note = opts.note, roles = roles, reference = "reference.wav", structure = structure,
  }
  local ok1 = fs.write_all(rev_dir .. "/timing.json", json.encode(current, { pretty = true }) .. "\n")
  local ok2 = fs.write_all(rev_dir .. "/publication.json", json.encode(info, { pretty = true }) .. "\n")
  if not (ok1 and ok2) then return nil, "publish_cannot_write", rev_dir end

  step("manifest")
  local built = manifest.build(fs, rev_dir, { kind = "publication", created = now.iso, meta = { song = song.id, revision = number }, yield = opts.yield })
  local wrote, werr = manifest.write(fs, rev_dir, built) -- the completion marker comes last
  if not wrote then return nil, "publish_cannot_write", werr end

  local actor
  for _, m in ipairs(band.members) do if m.id == band.producer then actor = m.name end end
  local facts = { { key = "stems", vars = { n = #roles } }, { key = "length", vars = { time = changelog.clock(current.length) } } }
  local logged, lerr = changelog.add(fs, pub_dir .. "/" .. changelog.file_name(S), song.title, {
    kind = "publication", revision = number, time = now, actor = actor, note = opts.note, facts = facts,
    structure = structure, tasks = opts.tasks,
  }, S)
  if not logged then return nil, "publish_cannot_write", lerr end

  return { revision = number, dir = rev_dir, pub_dir = pub_dir, roles = roles, structure = structure, timing = current }
end

return M
