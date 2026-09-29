local out = io.open((os.getenv("SPIKE_OUT_DIR") or ".") .. "/spike_lock.out", "w")
local function w(...) out:write(string.format(...), "\n") end

-- 1. actions with "lock" in the name (main section)
w("== actions matching 'lock' ==")
local i = 0
while true do
  local id, name = reaper.kbd_enumerateActions(0, i)
  if id == 0 then break end
  if name:lower():find("lock") and not name:lower():find("clock") and not name:lower():find("block") then
    w("%d\t%s", id, name)
  end
  i = i + 1
end

-- 2. build a project: one track with one item
reaper.InsertTrackAtIndex(0, false)
local tr = reaper.GetTrack(0, 0)
local item = reaper.AddMediaItemToTrack(tr)
reaper.SetMediaItemInfo_Value(item, "D_LENGTH", 2)

w("== item lock ==")
w("C_LOCK before: %s", tostring(reaper.GetMediaItemInfo_Value(item, "C_LOCK")))
reaper.SetMediaItemInfo_Value(item, "C_LOCK", 1)
w("C_LOCK after set 1: %s", tostring(reaper.GetMediaItemInfo_Value(item, "C_LOCK")))
local ok, ichunk = reaper.GetItemStateChunk(item, "", false)
w("item chunk has LOCK line: %s", tostring(ichunk:find("LOCK 1") ~= nil))

-- 3. track chunk and track-level lock
w("== track chunk (before) ==")
local _, chunk = reaper.GetTrackStateChunk(tr, "", false)
w("%s", (chunk:gsub("<ITEM.-\n>\n", "<ITEM...>\n")))
local newchunk = chunk:gsub("(\nNAME [^\n]*)", "%1\nLOCK 1", 1)
if not newchunk:find("LOCK 1") then newchunk = chunk:gsub("(\nPEAKCOL[^\n]*)", "%1\nLOCK 1", 1) end
local setok = reaper.SetTrackStateChunk(tr, newchunk, false)
tr = reaper.GetTrack(0, 0)
local _, chunk2 = reaper.GetTrackStateChunk(tr, "", false)
w("SetTrackStateChunk ok=%s, LOCK retained in re-read chunk: %s", tostring(setok), tostring(chunk2:find("\nLOCK 1") ~= nil))

-- 4. hiding / collapsing
w("== visibility ==")
w("B_SHOWINTCP=%s B_SHOWINMIXER=%s I_FOLDERDEPTH=%s I_FOLDERCOMPACT=%s",
  tostring(reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP")),
  tostring(reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER")),
  tostring(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")),
  tostring(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT")))

-- 5. track ext state round trip (for hidden markers, task 3.1)
w("== P_EXT ==")
reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:bandcollab_role", "bass", true)
local _, val = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:bandcollab_role", "", false)
w("P_EXT:bandcollab_role -> %s", tostring(val))

w("== API presence ==")
for _, n in ipairs({"ImGui_CreateContext", "ReaPack_GetRepositoryInfo", "SNM_GetIntConfigVar", "JS_Dialog_BrowseForFolder"}) do
  w("%s: %s", n, tostring(reaper.APIExists(n)))
end
out:close()
reaper.Main_OnCommand(40004, 0)
