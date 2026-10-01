-- @description Disable band guardian: stop starting it with REAPER
-- @version 0.0.1
local dir = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
local boot = dofile(dir .. "/bootstrap.lua")(dir)
local installer = require("bandcollab.guardian_install")
local fs = require("bandcollab.fs_std")
local S = boot.strings("fi")

installer.disable(fs, installer.startup_file(reaper.GetResourcePath()))
reaper.ShowMessageBox(S:t("guardian.disabled"), "Band Collab", 0)
