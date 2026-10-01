-- @description Create or open your own workspace for a song (members)
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
local picker = require("bandcollab.workspace_picker")
local fs = require("bandcollab.fs_std")
local view = require("picker_view")

local S = boot.strings("fi")
local settings = localsettings.new(localsettings.reaper_backend())
local band, member_or_code = firstrun.current(settings, fs)
if not band then
  reaper.ShowMessageBox(messages.get(S, member_or_code or "firstrun_needed").text, "Band Collab", 0)
  return
end
S.lang = band.language

local sess = picker.new(fs, band, settings:band_folder(), S, member_or_code)
sess:refresh()
local ctx = reaper.ImGui_CreateContext("bandcollab_picker")
local frames = 0

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 600, 420, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, S:t("ui.picker.title"), true)
  if visible then
    frames = frames + 1
    if not sess:running() and frames % 90 == 0 then sess:refresh() end -- new publications may have arrived
    local action, song = view.draw(ctx, sess)
    if action == "create" then sess:start_create(song)
    elseif action == "open" then sess:open(song) end
    if sess:running() then sess:step() end
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end
reaper.defer(loop)
