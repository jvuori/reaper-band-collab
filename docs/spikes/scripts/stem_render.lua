-- Spike 1.4: render per-track stems through a script and check what is baked in.
-- Env: STEM_DIR (working directory, must exist). Output: STEM_DIR/stem_render.out. REAPER quits when done.
local dir = assert(os.getenv("STEM_DIR"), "STEM_DIR not set")
local out = io.open(dir .. "/stem_render.out", "w")
local function w(...) out:write(string.format(...), "\n"); out:flush() end

-- 1. two test tones as 16-bit mono WAVs, amplitude 0.5, 2 s at 48 kHz
local function write_sine(path, freq)
  local n, sr, samples = 96000, 48000, {}
  for i = 0, n - 1 do samples[#samples + 1] = string.pack("<i2", math.floor(0.5 * 32767 * math.sin(2 * math.pi * freq * i / sr))) end
  local data = table.concat(samples)
  local f = io.open(path, "wb")
  f:write("RIFF", string.pack("<I4", 36 + #data), "WAVEfmt ", string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, sr, sr * 2, 2, 16), "data", string.pack("<I4", #data), data)
  f:close()
end
write_sine(dir .. "/tone_a.wav", 440)
write_sine(dir .. "/tone_b.wav", 880)

-- 2. project: track A (fader -6 dB, hard left), track B (volume automation -12 dB + FX -6 dB); master FX -20 dB
local function add_track(idx, name, wav)
  reaper.InsertTrackAtIndex(idx, false)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  reaper.SetOnlyTrackSelected(tr)
  reaper.SetEditCurPos(0, false, false)
  reaper.InsertMedia(wav, 0)
  return tr
end
local A = add_track(0, "stem_a", dir .. "/tone_a.wav")
local B = add_track(1, "stem_b", dir .. "/tone_b.wav")
reaper.SetMediaTrackInfo_Value(A, "D_VOL", 0.5)   -- -6 dB
reaper.SetMediaTrackInfo_Value(A, "D_PAN", -1.0)  -- hard left
local fxB = reaper.TrackFX_AddByName(B, "JS: Volume Adjustment", false, -1)
reaper.TrackFX_SetParam(B, fxB, 0, -6)            -- -6 dB on track B
local master = reaper.GetMasterTrack(0)
local fxM = reaper.TrackFX_AddByName(master, "JS: Volume Adjustment", false, -1)
reaper.TrackFX_SetParam(master, fxM, 0, -20)      -- -20 dB on the master bus

-- volume automation on B: constant 0.25 (-12 dB)
reaper.SetOnlyTrackSelected(B)
w("action 40406 is: %s", reaper.kbd_getTextFromCmd(40406, 0))
reaper.Main_OnCommand(40406, 0)
local env = reaper.GetTrackEnvelopeByName(B, "Volume")
w("volume envelope created: %s", tostring(env ~= nil))
if env then
  local v = reaper.ScaleToEnvelopeMode(reaper.GetEnvelopeScalingMode(env), 0.25)
  reaper.InsertEnvelopePoint(env, 0, v, 0, 0, false, true)
  reaper.Envelope_SortPoints(env)
end

-- 3. render helper
local function render(subdir, settings)
  os.execute('mkdir -p "' .. dir .. "/" .. subdir .. '"')
  reaper.GetSetProjectInfo_String(0, "RENDER_FILE", dir .. "/" .. subdir, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "$track", true)
  reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "ZXZhdxgAAQ==", true) -- WAV, 24 bit (verified below)
  reaper.GetSetProjectInfo(0, "RENDER_SRATE", 48000, true)
  reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 1, true) -- entire project
  reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", settings, true)
  reaper.GetSetProjectInfo(0, "RENDER_ADDTOPROJ", 0, true)
  reaper.SetTrackSelected(A, true); reaper.SetTrackSelected(B, true)
  reaper.Main_OnCommand(42230, 0)
end

-- 4. read a rendered WAV: bits, channels, peak per channel
local function analyze(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local s = f:read("a"); f:close()
  local pos, fmt = 13, nil
  local bits, ch, tag, dstart, dlen
  while pos < #s do
    local id, size = s:sub(pos, pos + 3), string.unpack("<I4", s, pos + 4)
    if id == "fmt " then tag, ch, _, _, _, bits = string.unpack("<I2I2I4I4I2I2", s, pos + 8)
    elseif id == "data" then dstart, dlen = pos + 8, size; break end
    pos = pos + 8 + size + (size % 2)
  end
  local bytes = bits // 8
  local peaks = { 0, 0 }
  local step = ch * bytes
  local fmtstr = (tag == 3) and (bits == 32 and "<f" or "<d") or ("<i" .. bytes)
  local scale = (tag == 3) and 1 or (2 ^ (bits - 1))
  for p = dstart, dstart + math.min(dlen, 48000 * step) - 1, step do   -- first second
    for c = 1, ch do
      local v = math.abs(string.unpack(fmtstr, s, p + (c - 1) * bytes)) / scale
      if v > peaks[c] then peaks[c] = v end
    end
  end
  return { bits = bits, ch = ch, tag = tag, peakL = peaks[1], peakR = peaks[2] }
end
local function db(x) return x > 0 and 20 * math.log(x, 10) or -math.huge end
local function report(label, file)
  local r = analyze(file)
  if not r then w("%s: FILE MISSING %s", label, file); return end
  w("%s: %d-bit, %d ch, peak L %.4f (%.1f dBFS)  peak R %.4f (%.1f dBFS)", label, r.bits, r.ch, r.peakL, db(r.peakL), r.peakR, db(r.peakR))
end
w("dry tone peak = 0.5000 (-6.0 dBFS)")

-- 5. variants: RENDER_SETTINGS values that produced per-track files in stem_settings_probe.lua
for _, v in ipairs({3, 32, 64, 128}) do
  local sub = "r_" .. v
  render(sub, v)
  report(string.format("settings %3d  stem A [fader -6 dB, pan left]   ", v), dir .. "/" .. sub .. "/stem_a.wav")
  report(string.format("settings %3d  stem B [FX -6 dB, auto -12 dB]   ", v), dir .. "/" .. sub .. "/stem_b.wav")
end
render("r_master", 0)         -- master mix, for reference
local h = io.popen('ls "' .. dir .. '/r_master/"'); local first = h:read("l"); h:close()
if first then report("master mix (A+B through -20 dB master)      ", dir .. "/r_master/" .. first) end
out:close()
reaper.Main_OnCommand(40004, 0)
