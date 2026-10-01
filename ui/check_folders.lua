-- @description Check the band folders (producer): report what is out of order, change nothing by itself
-- @version 0.0.1
local dir = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
local boot = dofile(dir .. "/bootstrap.lua")(dir)

if not reaper.APIExists("ImGui_CreateContext") then
  reaper.ShowMessageBox("ReaImGui is not installed. Install it with ReaPack (ReaTeam Extensions).", "Band Collab", 0)
  return
end

local firstrun = require("bandcollab.firstrun")
local localsettings = require("bandcollab.localsettings")
local messages = require("bandcollab.messages")
local foldercheck = require("bandcollab.foldercheck")
local fs = require("bandcollab.fs_std")
local view = require("folders_view")

local S = boot.strings("fi")
local settings = localsettings.new(localsettings.reaper_backend())
local band, member_or_code = firstrun.current(settings, fs)
if not band then
  reaper.ShowMessageBox(messages.get(S, member_or_code or "firstrun_needed").text, "Band Collab", 0)
  return
end
S.lang = band.language
local folder = settings:band_folder()
local state = { ran = false, problems = {}, tidy = {} }

local function run()
  state.problems, state.tidy = foldercheck.split(foldercheck.check(fs, band, folder))
  state.ran = true
end

local ctx = reaper.ImGui_CreateContext("bandcollab_check")
local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 640, 480, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, S:t("check.title"), true)
  if visible then
    local action, problem = view.draw(ctx, state, S)
    if action == "run" then run()
    elseif action == "delete" then foldercheck.fix(fs, folder, problem); run() end -- only what the person chose
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end
reaper.defer(loop)
