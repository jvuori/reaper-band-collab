-- @description Enable band guardian: start the guardian with REAPER
-- @version 0.0.1
local dir = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
local boot = dofile(dir .. "/bootstrap.lua")(dir)
local installer = require("bandcollab.guardian_install")
local fs = require("bandcollab.fs_std")
local S = boot.strings("fi")

local file = installer.startup_file(reaper.GetResourcePath())
local ok, err = installer.enable(fs, file, dir .. "/guardian_watch.lua")
if not ok then
  reaper.ShowMessageBox("Could not write " .. file .. ": " .. tostring(err), "Band Collab", 0)
  return
end
pcall(dofile, dir .. "/guardian_watch.lua") -- start it now as well
reaper.ShowMessageBox(S:t("guardian.enabled"), "Band Collab", 0)
