local out = io.open((os.getenv("SPIKE_OUT_DIR") or ".") .. "/spike_lock2.out", "w")
local function w(...) out:write(string.format(...), "\n") end
local function trackchunk(tr) local _, c = reaper.GetTrackStateChunk(tr, "", false); return (c:gsub("<ITEM.-\n>\n", "")) end
local function diff(a, b)
  local sa = {}; for l in a:gmatch("[^\n]+") do sa[l] = true end
  for l in b:gmatch("[^\n]+") do if not sa[l] then w("  + %s", l) end end
end

reaper.InsertTrackAtIndex(0, false)
reaper.InsertTrackAtIndex(1, false)
local tr = reaper.GetTrack(0, 0)
local it = reaper.AddMediaItemToTrack(tr); reaper.SetMediaItemInfo_Value(it, "D_LENGTH", 2)
local it2 = reaper.AddMediaItemToTrack(tr); reaper.SetMediaItemInfo_Value(it2, "D_POSITION", 3); reaper.SetMediaItemInfo_Value(it2, "D_LENGTH", 2)

local before = trackchunk(tr)
reaper.SetOnlyTrackSelected(tr)
reaper.Main_OnCommand(41312, 0) -- Track: Lock track controls
local locked = trackchunk(tr)
w("== lines added by action 41312 (Lock track controls) ==")
diff(before, locked)
reaper.Main_OnCommand(41313, 0) -- Unlock
local unlocked = trackchunk(tr)
w("== lines added by 41313 (Unlock) relative to locked ==")
diff(locked, unlocked)
w("unlock restores original chunk: %s", tostring(unlocked == before))

-- roundtrip: does a chunk written with the real lock line keep it?
reaper.Main_OnCommand(41312, 0)
local _, lc = reaper.GetTrackStateChunk(tr, "", false)
reaper.Main_OnCommand(41313, 0)
reaper.SetTrackStateChunk(tr, lc, false)
w("re-applied locked chunk keeps lock: %s", tostring(trackchunk(reaper.GetTrack(0,0)) == locked))

-- lock all items on selected tracks
reaper.SetOnlyTrackSelected(tr)
reaper.Main_OnCommand(43696, 0)
w("== 43696 lock all items on selected tracks == C_LOCK item1=%s item2=%s",
  tostring(reaper.GetMediaItemInfo_Value(it, "C_LOCK")), tostring(reaper.GetMediaItemInfo_Value(it2, "C_LOCK")))

-- hide from TCP/mixer and collapse a folder
local t2 = reaper.GetTrack(0, 1)
reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 1)
reaper.SetMediaTrackInfo_Value(t2, "I_FOLDERDEPTH", -1)
reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT", 2)
w("== folder collapse == compact=%s", tostring(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT")))
reaper.SetMediaTrackInfo_Value(t2, "B_SHOWINTCP", 0)
w("child hidden in TCP: %s", tostring(reaper.GetMediaTrackInfo_Value(t2, "B_SHOWINTCP")))

-- does the API respect lock? (it should not: scripts can still edit locked things)
reaper.SetOnlyTrackSelected(t2); reaper.Main_OnCommand(41312, 0)
reaper.SetMediaTrackInfo_Value(t2, "D_VOL", 0.5)
w("API volume set on locked track works: %s", tostring(reaper.GetMediaTrackInfo_Value(t2, "D_VOL") == 0.5))
out:close()
reaper.Main_OnCommand(40004, 0)
