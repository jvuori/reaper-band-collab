-- @description Proposals (producer): review a member's proposal and take it into the master
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
local import_session = require("bandcollab.import_session")
local fs = require("bandcollab.fs_std")
local view = require("import_view")

local S = boot.strings("fi")
local settings = localsettings.new(localsettings.reaper_backend())
local band, member_or_code = firstrun.current(settings, fs)
if not band then
  reaper.ShowMessageBox(messages.get(S, member_or_code or "firstrun_needed").text, "Band Collab", 0)
  return
end
S.lang = band.language

local sess, code = import_session.new(fs, band, settings:band_folder(), S, member_or_code)
if not sess then
  reaper.ShowMessageBox(messages.get(S, code).text, "Band Collab", 0)
  return
end
sess:refresh()

local ctx = reaper.ImGui_CreateContext("bandcollab_import")
local frames = 0

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 680, 560, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, S:t("ui.import.title"), true)
  if visible then
    frames = frames + 1
    if not sess:running() and frames % 60 == 0 then sess:refresh() end -- new proposals may have arrived
    local action, entry = view.draw(ctx, sess)
    if action == "review" then sess:review(entry)
    elseif action == "accept" then sess:start_import()
    elseif action == "cancel" then sess:cancel()
    elseif action == "undo" then sess:undo() end
    if sess:running() then sess:step() end
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end
reaper.defer(loop)
