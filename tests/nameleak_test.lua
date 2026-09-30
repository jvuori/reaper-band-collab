-- Requirement "no band-specific content is built in": the extension must not contain the name of
-- the band it was first written for (tests and documentation may use it as an example).
-- Needs REAPER for directory listing and project creation (run through tests/reaper_runner.lua).
local t = require("luatest")
local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

local ORIGINAL_BAND = "muuri" -- example band; must not appear in the extension itself

local function read(path) local f = io.open(path, "rb"); if not f then return nil end; local s = f:read("a"); f:close(); return s end

local function files_under(fs, dir, out)
  for _, e in ipairs(fs.list(dir) or {}) do
    if e.is_dir then files_under(fs, dir .. "/" .. e.name, out) else out[#out + 1] = dir .. "/" .. e.name end
  end
  return out
end

local function tmpdir() local d = os.tmpname(); os.remove(d); return d end

t.test("the extension's code, UI, strings and package index do not contain the original band's name", function()
  need_reaper()
  local fs = require("bandcollab.fs_std")
  local checked = 0
  for _, sub in ipairs({ "lib", "ui", "strings", "reapack" }) do
    for _, file in ipairs(files_under(fs, TEST_ROOT .. "/" .. sub, {})) do
      local text = read(file) or ""
      t.falsy(text:lower():find(ORIGINAL_BAND, 1, true), "found the band name in " .. file)
      t.falsy(file:sub(#TEST_ROOT + 1):lower():find(ORIGINAL_BAND, 1, true), "band name in the file name " .. file)
      checked = checked + 1
    end
  end
  t.truthy(checked > 20, "only " .. checked .. " files were scanned")
end)

t.test("a differently named band leaves no trace of the original name anywhere it creates", function()
  need_reaper()
  local wizard, projects = require("bandcollab.wizard"), require("bandcollab.projects")
  local strings, fs = require("bandcollab.strings"), require("bandcollab.fs_std")
  local pm = require("bandcollab.projectmodel")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")

  local dir = tmpdir()
  local state = wizard.new("en")
  state.name = "Zebra Trio"
  local m = wizard.add_member(state, "Kim"); state.members[m].instruments[1] = { label = "Guitar", tracks = 2 }
  local n = wizard.add_member(state, "Lee"); state.members[n].instruments[1] = { label = "Drums", tracks = 3 }
  t.truthy(wizard.create(fs, projects, dir, state, S))
  local file = projects.create_song(fs, dir .. "/template/song-template.rpp", dir .. "/producer", "First Song")
  t.truthy(file)

  local seen = 0
  for _, path in ipairs(files_under(fs, dir, {})) do
    t.falsy(path:sub(#dir + 1):lower():find(ORIGINAL_BAND, 1, true), "band name in path " .. path)
    local text = read(path) or ""
    t.falsy(text:lower():find(ORIGINAL_BAND, 1, true), "band name in the content of " .. path)
    seen = seen + 1
  end
  t.truthy(seen >= 3, "expected band.json, template and song, saw " .. seen)

  -- stored keys: the extended-state section and the project markers use neutral names
  local localsettings = require("bandcollab.localsettings")
  t.falsy(localsettings.SECTION:lower():find(ORIGINAL_BAND, 1, true))
  for _, key in ipairs({ pm.KEY_ROLE, pm.KEY_OWNER, pm.SECTION, pm.KEY_KIND, pm.KEY_BAND }) do
    t.falsy(key:lower():find(ORIGINAL_BAND, 1, true), "marker key " .. key)
  end
  os.execute("rm -rf '" .. dir .. "'")
end)
