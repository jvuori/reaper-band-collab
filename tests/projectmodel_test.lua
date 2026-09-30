-- Needs REAPER (run through tests/reaper_runner.lua); skipped in plain Lua.
local t = require("luatest")

local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" }, { id = "drums", label = "Rummut" }, { id = "keys", label = "Koskettimet" } },
  members = {
    { id = "aino", name = "Aino", roles = { "bass" } },
    { id = "eero", name = "Eero", roles = { "drums", "keys" } },
  },
  locations = { master = "M", publications = "P", proposals = "E" },
}

local function tmpdir()
  local d = os.tmpname(); os.remove(d)
  reaper.RecursiveCreateDirectory(d, 0)
  return d
end

local function summary(list)
  local out = {}
  for _, f in ipairs(list) do out[#out + 1] = string.format("%s/%s/%d", f.role, tostring(f.owner), f.children) end
  return table.concat(out, ",")
end

local function build()
  local pm = require("bandcollab.projectmodel")
  local template = require("bandcollab.template")
  pm.clear(0)
  pm.apply_plan(0, template.plan(band, { bass = 2, drums = 3 }))
  return pm
end

t.test("role folders are found with role, owner and children after building", function()
  need_reaper()
  local pm = build()
  local found = pm.role_folders(0)
  t.eq(summary(found), "bass/aino/2,drums/eero/3,keys/eero/1")
  t.eq(found[1].index, 1)
  t.eq(found[2].index, 4)
  t.eq(found[3].index, 8)
end)

t.test("markers survive save and reopen", function()
  need_reaper()
  local pm = build()
  local dir = tmpdir()
  local file = dir .. "/song.rpp"
  reaper.Main_SaveProjectEx(0, file, 0)
  pm.clear(0)
  t.eq(#pm.role_folders(0), 0)
  reaper.Main_openProject("noprompt:" .. file)
  t.eq(summary(pm.role_folders(0)), "bass/aino/2,drums/eero/3,keys/eero/1")
  os.execute("rm -rf '" .. dir .. "'")
end)

t.test("renaming a folder track does not change its role or owner", function()
  need_reaper()
  local pm = build()
  local f = pm.role_folders(0)[2]
  reaper.GetSetMediaTrackInfo_String(f.track, "P_NAME", "Something else entirely", true)
  local after = pm.role_folders(0)[2]
  t.eq(after.name, "Something else entirely")
  t.eq(after.role, "drums")
  t.eq(after.owner, "eero")
end)

t.test("a track that only looks like a role folder (same name, no marker) is not one", function()
  need_reaper()
  local pm = build()
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
  local extra = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(extra, "P_NAME", "Basso - Aino", true)
  reaper.SetMediaTrackInfo_Value(extra, "I_FOLDERDEPTH", 1)
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
  reaper.SetMediaTrackInfo_Value(reaper.GetTrack(0, reaper.CountTracks(0) - 1), "I_FOLDERDEPTH", -1)
  t.eq(#pm.role_folders(0), 3)
end)

t.test("role_of_track finds the role of any track inside a role folder", function()
  need_reaper()
  local pm = build()
  local drums = pm.role_folders(0)[2]
  t.eq(pm.role_of_track(0, reaper.GetTrack(0, drums.index)), "drums")      -- first child
  t.eq(pm.role_of_track(0, reaper.GetTrack(0, drums.last - 1)), "drums")   -- last child
  t.eq(pm.role_of_track(0, drums.track), "drums")
end)

t.test("a track moved out of its folder no longer belongs to the role", function()
  need_reaper()
  local pm = build()
  local bass = pm.role_folders(0)[1]
  local child = reaper.GetTrack(0, bass.last - 1)
  reaper.SetOnlyTrackSelected(child)
  reaper.ReorderSelectedTracks(reaper.CountTracks(0), 0) -- move to the end, outside every folder
  local moved = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  t.eq(pm.role_of_track(0, moved), nil)
  t.eq(pm.role_folders(0)[1].children, 1)
end)

t.test("recording path is relative to the project and survives save and reopen", function()
  need_reaper()
  local pm = build()
  pm.set_recording_path(0)
  local dir = tmpdir()
  reaper.Main_SaveProjectEx(0, dir .. "/song.rpp", 0)
  pm.clear(0)
  reaper.Main_openProject("noprompt:" .. dir .. "/song.rpp")
  t.eq(pm.recording_path(0), "media")
  os.execute("rm -rf '" .. dir .. "'")
end)

t.test("a member who owns several roles gets all of those folders, and only those", function()
  need_reaper()
  local pm = build()
  local function roles(list) local o = {}; for _, f in ipairs(list) do o[#o + 1] = f.role end; return table.concat(o, ",") end
  t.eq(roles(pm.owned_folders(0, band, "aino")), "bass")
  t.eq(roles(pm.owned_folders(0, band, "eero")), "drums,keys")
  t.eq(roles(pm.owned_folders(0, band, "nobody")), "")
end)

t.test("ownership follows band.json, not the owner marker stored on the folder", function()
  need_reaper()
  local pm = build()
  local bass = pm.role_folders(0)[1]
  pm.set_marker(bass.track, pm.KEY_OWNER, "eero")   -- stale marker says someone else
  t.eq(#pm.owned_folders(0, band, "aino"), 1)
  t.eq(pm.owned_folders(0, band, "aino")[1].role, "bass")
  t.eq(#pm.owned_folders(0, band, "eero"), 2)
end)
