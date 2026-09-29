-- Spike 1.4b: which RENDER_SETTINGS values produce per-track stem files?
-- Env: STEM_DIR (must contain tone_a.wav and tone_b.wav from stem_render.lua). Output: STEM_DIR/settings_probe.out
local dir = assert(os.getenv("STEM_DIR"), "STEM_DIR not set")
local out = io.open(dir .. "/settings_probe.out", "w")
local function add_track(idx, name, wav)
  reaper.InsertTrackAtIndex(idx, false)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  reaper.SetOnlyTrackSelected(tr); reaper.SetEditCurPos(0, false, false); reaper.InsertMedia(wav, 0)
  return tr
end
local A = add_track(0, "stem_a", dir .. "/tone_a.wav")
local B = add_track(1, "stem_b", dir .. "/tone_b.wav")
local values = {}
for v = 0, 47 do values[#values + 1] = v end
for _, v in ipairs({64, 128, 129, 130, 131, 132, 136, 192, 256, 512}) do values[#values + 1] = v end
for _, v in ipairs(values) do
  local sub = dir .. "/p_" .. v
  os.execute('mkdir -p "' .. sub .. '"')
  reaper.GetSetProjectInfo_String(0, "RENDER_FILE", sub, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "$track", true)
  reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "ZXZhdxgAAQ==", true)
  reaper.GetSetProjectInfo(0, "RENDER_SRATE", 48000, true)
  reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 1, true)
  reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", v, true)
  reaper.GetSetProjectInfo(0, "RENDER_ADDTOPROJ", 0, true)
  reaper.SetTrackSelected(A, true); reaper.SetTrackSelected(B, true)
  reaper.Main_OnCommand(42230, 0)
  local h = io.popen('ls "' .. sub .. '" | tr "\\n" " "'); local files = h:read("a"); h:close()
  out:write(string.format("%3d -> %s\n", v, files)); out:flush()
end
out:close()
reaper.Main_OnCommand(40004, 0)
