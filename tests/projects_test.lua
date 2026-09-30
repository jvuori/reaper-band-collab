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

local function tab_count() local n = 0; while reaper.EnumProjects(n) do n = n + 1 end; return n end

local function summary(list)
  local out = {}
  for _, f in ipairs(list) do out[#out + 1] = string.format("%s/%s/%d", f.role, tostring(f.owner), f.children) end
  return table.concat(out, ",")
end

t.test("a template is created for a three-member band and leaves the open project alone", function()
  need_reaper()
  local fs, projects = require("bandcollab.fs_std"), require("bandcollab.projects")
  local pm = require("bandcollab.projectmodel")
  local dir = tmpdir()
  pm.clear(0)
  reaper.InsertTrackAtIndex(0, false)
  reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, 0), "P_NAME", "my own work", true)
  local tabs = tab_count()

  local ok, err = projects.create_template(fs, band, { bass = 2, drums = 3 }, dir .. "/template/song-template.rpp")
  t.truthy(ok, err)
  t.truthy(fs.exists(dir .. "/template/song-template.rpp"))
  t.eq(tab_count(), tabs)
  t.eq(reaper.CountTracks(0), 1)
  local _, name = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, 0), "P_NAME", "", false)
  t.eq(name, "my own work")
  pm.clear(0)
  os.execute("rm -rf '" .. dir .. "'")
end)

t.test("a song made from the template has the folders in the agreed order with markers", function()
  need_reaper()
  local fs, projects = require("bandcollab.fs_std"), require("bandcollab.projects")
  local pm = require("bandcollab.projectmodel")
  local dir = tmpdir()
  t.truthy(projects.create_template(fs, band, { bass = 2, drums = 3 }, dir .. "/template.rpp"))
  local tabs = tab_count()
  local file, name = projects.create_song(fs, dir .. "/template.rpp", dir .. "/songs", "Yö: kuka? Minä", { keep_open = true })
  t.truthy(file, name)
  t.eq(name, "yo-kuka-mina")
  t.eq(file, dir .. "/songs/yo-kuka-mina/yo-kuka-mina.rpp")
  t.truthy(fs.exists(file))
  t.eq(tab_count(), tabs + 1)

  local proj = (reaper.EnumProjects(-1))
  t.eq(summary(pm.role_folders(proj)), "bass/aino/2,drums/eero/3,keys/eero/1")
  t.eq(pm.get_project_marker(proj, "kind"), "song")
  t.eq(pm.get_project_marker(proj, "band_name"), "Example Band")
  t.eq(pm.recording_path(proj), "media")
  local _, title = reaper.GetSetProjectInfo_String(proj, "PROJECT_TITLE", "", false)
  t.eq(title, "Yö: kuka? Minä")

  reaper.SelectProjectInstance(proj); reaper.Main_OnCommand(40860, 0) -- close the song's tab
  os.execute("rm -rf '" .. dir .. "'")
end)

t.test("the template itself is not modified by creating songs", function()
  need_reaper()
  local fs, projects = require("bandcollab.fs_std"), require("bandcollab.projects")
  local dir = tmpdir()
  t.truthy(projects.create_template(fs, band, nil, dir .. "/template.rpp"))
  local before = fs.read_all(dir .. "/template.rpp")
  t.truthy(projects.create_song(fs, dir .. "/template.rpp", dir .. "/songs", "A"))
  t.eq(fs.read_all(dir .. "/template.rpp"), before)
  local template_marker = before:find("template", 1, true)
  t.truthy(template_marker)
  os.execute("rm -rf '" .. dir .. "'")
end)

t.test("songs with the same title get unique folders, case-insensitively", function()
  need_reaper()
  local fs, projects = require("bandcollab.fs_std"), require("bandcollab.projects")
  local dir = tmpdir()
  t.truthy(projects.create_template(fs, band, nil, dir .. "/template.rpp"))
  local _, n1 = projects.create_song(fs, dir .. "/template.rpp", dir .. "/songs", "Kappale")
  local _, n2 = projects.create_song(fs, dir .. "/template.rpp", dir .. "/songs", "KAPPALE")
  local _, n3 = projects.create_song(fs, dir .. "/template.rpp", dir .. "/songs", "kappale")
  t.eq(n1, "kappale"); t.eq(n2, "kappale-2"); t.eq(n3, "kappale-3")
  os.execute("rm -rf '" .. dir .. "'")
end)

t.test("a missing template gives an error, not a crash or a stray folder", function()
  need_reaper()
  local fs, projects = require("bandcollab.fs_std"), require("bandcollab.projects")
  local dir = tmpdir()
  local file, err = projects.create_song(fs, dir .. "/nope.rpp", dir .. "/songs", "X")
  t.eq(file, nil)
  t.truthy(err:find("template not found"))
  t.falsy(fs.exists(dir .. "/songs"))
  os.execute("rm -rf '" .. dir .. "'")
end)
