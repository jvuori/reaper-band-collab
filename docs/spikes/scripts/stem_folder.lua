-- Spike 1.4c: what does a stem contain when tracks live in a folder with bus processing?
-- Env: STEM_DIR (needs tone_a.wav, tone_b.wav). Output: STEM_DIR/stem_folder.out
local dir = assert(os.getenv("STEM_DIR"), "STEM_DIR not set")
local out = io.open(dir .. "/stem_folder.out", "w")
local function w(...) out:write(string.format(...), "\n"); out:flush() end
local function add_track(idx, name, wav)
  reaper.InsertTrackAtIndex(idx, false)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  if wav then reaper.SetOnlyTrackSelected(tr); reaper.SetEditCurPos(0, false, false); reaper.InsertMedia(wav, 0) end
  return tr
end
-- folder "bus" (fader -6 dB, FX -6 dB) with children a and b (both dry, both centred)
local F = add_track(0, "bus", nil)
local A = add_track(1, "kid_a", dir .. "/tone_a.wav")
local B = add_track(2, "kid_b", dir .. "/tone_b.wav")
reaper.SetMediaTrackInfo_Value(F, "I_FOLDERDEPTH", 1)
reaper.SetMediaTrackInfo_Value(B, "I_FOLDERDEPTH", -1)
reaper.SetMediaTrackInfo_Value(F, "D_VOL", 0.5)                       -- -6 dB fader on the bus
local fx = reaper.TrackFX_AddByName(F, "JS: Volume Adjustment", false, -1)
reaper.TrackFX_SetParam(F, fx, 0, -6)                                 -- -6 dB FX on the bus

local function render(sub, tracks)
  os.execute('mkdir -p "' .. dir .. "/" .. sub .. '"')
  reaper.GetSetProjectInfo_String(0, "RENDER_FILE", dir .. "/" .. sub, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "$track", true)
  reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "ZXZhdxgAAQ==", true)
  reaper.GetSetProjectInfo(0, "RENDER_SRATE", 48000, true)
  reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 1, true)
  reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 3, true)
  reaper.GetSetProjectInfo(0, "RENDER_ADDTOPROJ", 0, true)
  for i = 0, reaper.CountTracks(0) - 1 do reaper.SetTrackSelected(reaper.GetTrack(0, i), false) end
  for _, t in ipairs(tracks) do reaper.SetTrackSelected(t, true) end
  reaper.Main_OnCommand(42230, 0)
end
local function peak(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local s = f:read("a"); f:close()
  local pos = 13
  while pos < #s do
    local id, size = s:sub(pos, pos + 3), string.unpack("<I4", s, pos + 4)
    if id == "data" then
      local m = 0
      for p = pos + 8, pos + 8 + math.min(size, 48000 * 6) - 1, 3 do
        local v = math.abs(string.unpack("<i3", s, p)) / 2 ^ 23
        if v > m then m = v end
      end
      return m
    end
    pos = pos + 8 + size + (size % 2)
  end
end
local function list(sub) local h = io.popen('ls "' .. dir .. "/" .. sub .. '" | tr "\\n" " "'); local r = h:read("a"); h:close(); return r end
w("dry tones: 0.5 each (a is 440 Hz, b is 880 Hz, they never both peak at the same time exactly)")
render("f_children", { A, B })
w("children selected -> files: %s", list("f_children"))
w("  kid_a peak %.4f   kid_b peak %.4f   (0.5 would mean no bus processing; 0.125 would mean bus -12 dB included)", peak(dir .. "/f_children/kid_a.wav") or -1, peak(dir .. "/f_children/kid_b.wav") or -1)
render("f_folder", { F })
w("folder track selected -> files: %s", list("f_folder"))
w("  bus peak %.4f   (sum of both tones through bus -12 dB; unprocessed sum would peak up to 1.0)", peak(dir .. "/f_folder/bus.wav") or -1)
out:close()
reaper.Main_OnCommand(40004, 0)
