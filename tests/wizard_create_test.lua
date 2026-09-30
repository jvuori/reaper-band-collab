-- Needs REAPER (run through tests/reaper_runner.lua); skipped in plain Lua.
local t = require("luatest")
local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

t.test("the wizard creates band.json and a template for a three-member band, and a song can be made from it", function()
  need_reaper()
  local wizard = require("bandcollab.wizard")
  local bandfile = require("bandcollab.bandfile")
  local projects = require("bandcollab.projects")
  local pm = require("bandcollab.projectmodel")
  local strings = require("bandcollab.strings")
  local fs = require("bandcollab.fs_std")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")

  local dir = os.tmpname(); os.remove(dir)
  local state = wizard.new("fi")
  state.name = "Example Band"
  local a = wizard.add_member(state, "Aino"); state.members[a].instruments[1] = { label = "Basso", tracks = 2 }
  local e = wizard.add_member(state, "Eero"); state.members[e].instruments[1] = { label = "Rummut", tracks = 4 }
  wizard.add_instrument(state, e, "Koskettimet", 1)
  local p = wizard.add_member(state, "Pia"); state.members[p].instruments[1] = { label = "Laulu", tracks = 1 }

  local band, err = wizard.create(fs, projects, dir, state, S)
  t.truthy(band, err and err[1] and err[1].code)

  -- band.json is valid and complete
  local read = bandfile.read(fs, dir)
  t.truthy(read)
  t.eq(#read.members, 3)
  t.eq(#read.roles, 4)
  t.eq(read.producer, "aino")
  t.truthy(fs.exists(dir .. "/tuottaja") or #fs.list(dir) > 0)
  local names = {}
  for _, entry in ipairs(fs.list(dir)) do names[entry.name] = entry.is_dir end
  t.eq(names["tuottaja"], true); t.eq(names["julkaisut"], true); t.eq(names["ehdotukset"], true)
  t.eq(names["template"], true); t.eq(names["band.json"], false)

  -- a song made from the template has the band's structure
  local file = projects.create_song(fs, dir .. "/template/song-template.rpp", dir .. "/tuottaja", "Ensimmäinen", { keep_open = true })
  t.truthy(file)
  local proj = (reaper.EnumProjects(-1))
  local found = pm.role_folders(proj)
  local out = {}
  for _, f in ipairs(found) do out[#out + 1] = string.format("%s/%s/%d", f.role, f.owner, f.children) end
  t.eq(table.concat(out, ","), "basso/aino/2,rummut/eero/4,koskettimet/eero/1,laulu/pia/1")
  t.eq(#pm.owned_folders(proj, read, "eero"), 2)

  reaper.SelectProjectInstance(proj); reaper.Main_OnCommand(40860, 0)
  os.execute("rm -rf '" .. dir .. "'")
end)

t.test("the wizard leaves nothing behind when the input is invalid", function()
  need_reaper()
  local wizard = require("bandcollab.wizard")
  local projects = require("bandcollab.projects")
  local strings = require("bandcollab.strings")
  local fs = require("bandcollab.fs_std")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")
  local dir = os.tmpname(); os.remove(dir)
  local made, problems = wizard.create(fs, projects, dir, wizard.new("fi"), S)
  t.eq(made, nil)
  t.truthy(#problems > 0)
  t.falsy(fs.exists(dir .. "/band.json"))
  t.eq(#(fs.list(dir) or {}), 0)
end)
