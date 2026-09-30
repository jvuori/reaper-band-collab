-- Runs the *_test.lua files inside REAPER's own Lua, so REAPER-specific code paths are tested.
-- Env: BANDCOLLAB_ROOT (repo root), TEST_OUT (result file). Optional TEST_FILES (space separated
-- file names inside tests/). REAPER quits when the run is finished.
--   reaper -cfgfile <profile>/reaper.ini -nosplash -newinst tests/reaper_runner.lua
local root = assert(os.getenv("BANDCOLLAB_ROOT"), "BANDCOLLAB_ROOT not set")
local out_path = assert(os.getenv("TEST_OUT"), "TEST_OUT not set")
_G.TEST_ROOT = root
package.path = table.concat({ root .. "/?.lua", root .. "/lib/?.lua", root .. "/tests/?.lua", package.path }, ";")

-- Quits REAPER without ever waiting for a person: an open project with unsaved changes would make
-- the normal quit action ask "save changes?" in a modal dialog, so in that case exit directly.
local function safe_quit()
  local i = 0
  while true do
    local p = reaper.EnumProjects(i, "")
    if not p then break end
    if reaper.IsProjectDirty(p) ~= 0 then os.exit(0, true) end
    i = i + 1
  end
  reaper.Main_OnCommand(40004, 0)
end

local luatest = require("luatest")
local lines, total_failed = {}, 0

local files = {}
if os.getenv("TEST_FILES") and os.getenv("TEST_FILES") ~= "" then
  for name in os.getenv("TEST_FILES"):gmatch("%S+") do files[#files + 1] = name end
else
  local i = 0
  while true do
    local name = reaper.EnumerateFiles(root .. "/tests", i)
    if not name then break end
    if name:match("_test%.lua$") then files[#files + 1] = name end
    i = i + 1
  end
  table.sort(files)
end

for _, name in ipairs(files) do
  local chunk, err = loadfile(root .. "/tests/" .. name)
  if not chunk then
    lines[#lines + 1] = "FAIL " .. name .. ": cannot load: " .. tostring(err)
    total_failed = total_failed + 1
  else
    local ok, lerr = pcall(chunk)
    if not ok then
      lines[#lines + 1] = "FAIL " .. name .. ": " .. tostring(lerr)
      total_failed = total_failed + 1
    else
      local passed, failed, failures, skipped = luatest.run()
      for _, f in ipairs(failures) do lines[#lines + 1] = "FAIL " .. name .. ": " .. f end
      for _, s in ipairs(skipped) do lines[#lines + 1] = "SKIP " .. name .. ": " .. s end
      lines[#lines + 1] = string.format("%s: %d passed, %d failed, %d skipped", name, passed, failed, #skipped)
      total_failed = total_failed + failed
    end
  end
end
lines[#lines + 1] = total_failed == 0 and "RESULT: ok" or ("RESULT: " .. total_failed .. " failed")

local f = io.open(out_path, "w")
f:write(table.concat(lines, "\n"), "\n")
f:close()
safe_quit()
