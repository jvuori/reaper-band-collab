-- Shared fixture for tests that need REAPER: a band on disk, a registered song with real audio in
-- the band folder (opened as the current project), and helpers to measure rendered audio.
local M = {}

local band = {
  schema = 1, name = "Example Band", language = "en", producer = "aino",
  roles = { { id = "bass", label = "Bass" }, { id = "drums", label = "Drums" } },
  members = { { id = "aino", name = "Aino", roles = { "bass" } }, { id = "eero", name = "Eero", roles = { "drums" } } },
  locations = { master = "producer", publications = "publications", proposals = "proposals" },
}

local function write_tone(path, freq, seconds)
  local n, sr, samples = 48000 * seconds, 48000, {}
  for i = 0, n - 1 do samples[#samples + 1] = string.pack("<i2", math.floor(0.5 * 32767 * math.sin(2 * math.pi * freq * i / sr))) end
  local data = table.concat(samples)
  local f = assert(io.open(path, "wb"))
  f:write("RIFF", string.pack("<I4", 36 + #data), "WAVEfmt ", string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, sr, sr * 2, 2, 16), "data", string.pack("<I4", #data), data)
  f:close()
end

-- peak and length (seconds) of a rendered PCM WAV (first channel pair)
local function analyze(path)
  local f = assert(io.open(path, "rb")); local s = f:read("a"); f:close()
  local pos, bits, ch, rate, dstart, dlen = 13
  while pos < #s do
    local id, size = s:sub(pos, pos + 3), string.unpack("<I4", s, pos + 4)
    if id == "fmt " then _, ch, rate, _, _, bits = string.unpack("<I2I2I4I4I2I2", s, pos + 8)
    elseif id == "data" then dstart, dlen = pos + 8, size; break end
    pos = pos + 8 + size + (size % 2)
  end
  local bytes = bits // 8
  local peak = 0
  local scale = 2 ^ (bits - 1)
  for p = dstart, dstart + dlen - 1, bytes * ch * 8 do
    for c = 0, ch - 1 do
      local v = math.abs(string.unpack("<i" .. bytes, s, p + c * bytes)) / scale
      if v > peak then peak = v end
    end
  end
  return { peak = peak, seconds = dlen / (bytes * ch * rate), rate = rate, channels = ch }
end

local function read(path) local f = io.open(path, "rb"); if not f then return nil end; local s = f:read("a"); f:close(); return s end

-- Builds the fixture: a registered song in the band folder, opened as the current project.
local function fixture()
  local fs = require("bandcollab.fs_std")
  local bandfile = require("bandcollab.bandfile")
  local projects = require("bandcollab.projects")
  local pm = require("bandcollab.projectmodel")
  local template = require("bandcollab.template")
  local receive = require("bandcollab.receive")

  local root = os.tmpname(); os.remove(root)
  local band_folder = root .. "/band"
  for _, d in ipairs({ "producer", "publications", "proposals" }) do fs.mkdirs(band_folder .. "/" .. d) end
  assert(bandfile.write(fs, band_folder, band))
  assert(projects.create_template(fs, band, { bass = 1, drums = 1 }, band_folder .. "/template/song-template.rpp"))
  local staged = assert(projects.create_song(fs, band_folder .. "/template/song-template.rpp", root .. "/stage", "Test Song", { keep_open = true }))
  local proj = (reaper.EnumProjects(-1))

  local dir = staged:match("^(.*)/[^/]*$")
  fs.mkdirs(dir .. "/media")
  write_tone(dir .. "/media/bass-tone.wav", 440, 3)
  write_tone(dir .. "/media/drum-tone.wav", 880, 3)
  local folders = pm.role_folders(proj)
  for i, f in ipairs(folders) do
    local child = reaper.GetTrack(proj, f.index) -- first track inside the folder
    reaper.SetOnlyTrackSelected(child)
    reaper.SetEditCurPos(0, false, false)
    reaper.InsertMedia(dir .. "/media/" .. (i == 1 and "bass" or "drum") .. "-tone.wav", 0)
  end
  -- folder processing: bass folder fader -6 dB; drums folder gets a -6 dB effect
  reaper.SetMediaTrackInfo_Value(folders[1].track, "D_VOL", 0.5)
  local fx = reaper.TrackFX_AddByName(folders[2].track, "JS: Volume Adjustment", false, -1)
  reaper.TrackFX_SetParam(folders[2].track, fx, 0, -6)
  -- master-bus processing: -20 dB, which stems must NOT contain and the reference mix must
  local master = reaper.GetMasterTrack(proj)
  local mfx = reaper.TrackFX_AddByName(master, "JS: Volume Adjustment", false, -1)
  reaper.TrackFX_SetParam(master, mfx, 0, -20)
  reaper.SelectProjectInstance(proj); reaper.Main_OnCommand(40026, 0) -- the song tab is bound to its own file
  reaper.Main_OnCommand(40860, 0)

  -- receive it into the band folder and open the registered master
  local ctx = assert(receive.context(fs, band, band_folder))
  local cand = receive.candidates(ctx, root .. "/stage")[1]
  local entry = assert(receive.import(ctx, cand, { library = "rehearsals", cycle = "2026-09-29", now = "2026-09-29T20:00:00Z" }))
  local master_file = band_folder .. "/" .. entry.path .. "/" .. entry.slug .. ".rpp"
  reaper.Main_OnCommand(40859, 0)
  reaper.Main_openProject("noprompt:" .. master_file)
  return { fs = fs, root = root, band_folder = band_folder, entry = entry, proj = (reaper.EnumProjects(-1)), master_file = master_file }
end

local function cleanup(fx)
  reaper.SelectProjectInstance(fx.proj); reaper.Main_OnCommand(40860, 0)
  os.execute("rm -rf '" .. fx.root .. "'")
end

local NOW = { display = "2026-09-29 22:00", iso = "2026-09-29T22:00:00+03:00" }

-- A master published as r1, and the song entry a member sees for it.
function M.published()
  local publisher, strings = require("bandcollab.publisher"), require("bandcollab.strings")
  local songs_list = require("bandcollab.songs_list")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  local fx = fixture()
  assert(publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { now = NOW }))
  return fx, songs_list.list(fx.fs, band, fx.band_folder).songs[1], S
end

-- Publishes the master again (after `change(proj)` altered and saved it) and returns the new song entry.
function M.republish(fx, S, change)
  local publisher = require("bandcollab.publisher")
  reaper.SelectProjectInstance(fx.proj)
  if change then change(fx.proj) end
  reaper.SelectProjectInstance(fx.proj); reaper.Main_OnCommand(40026, 0)
  assert(publisher.publish(fx.fs, band, fx.band_folder, fx.proj, S, { now = NOW }))
  return require("bandcollab.songs_list").list(fx.fs, band, fx.band_folder).songs[1]
end

-- Renders one folder track of a project as a stem and returns the measurements of the file.
function M.render_folder(proj, folder_track, dir, name)
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
  return analyze(dir .. "/" .. name .. ".wav")
end

M.band, M.write_tone, M.analyze, M.read, M.fixture, M.cleanup, M.NOW = band, write_tone, analyze, read, fixture, cleanup, NOW
return M
