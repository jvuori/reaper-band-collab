-- @description Synkronoi (members): get the latest master and propose your work
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
local sync = require("bandcollab.workspace_sync")
local sync_session = require("bandcollab.sync_session")
local fs = require("bandcollab.fs_std")
local view = require("sync_view")

local S = boot.strings("fi")
local settings = localsettings.new(localsettings.reaper_backend())
local band, member_or_code = firstrun.current(settings, fs)
if not band then
  reaper.ShowMessageBox(messages.get(S, member_or_code or "firstrun_needed").text, "Band Collab", 0)
  return
end
S.lang = band.language

local ctx = reaper.ImGui_CreateContext("bandcollab_sync")
local sess
local frames_since_refresh = 0

-- the panel works on the workspace that is open in the active project tab
local function attach()
  local ws = sync.identify(fs, (reaper.EnumProjects(-1)))
  if ws and ws.state.member ~= member_or_code then ws = nil end
  if not ws then sess = nil; return end
  if not sess or sess.ws.file ~= ws.file then sess = sync_session.new(fs, band, settings:band_folder(), S, ws) end
  sess.ws.proj, sess.ws.state = ws.proj, ws.state
  sess:refresh()
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 620, 560, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, S:t("ui.sync.title"), true)
  if visible then
    frames_since_refresh = frames_since_refresh + 1
    if not (sess and sess:running()) and (frames_since_refresh >= 30 or not sess) then attach(); frames_since_refresh = 0 end
    if not sess then
      reaper.ImGui_TextColored(ctx, 0xE6A700FF, S:t("err.workspace_missing.what"))
      reaper.ImGui_TextWrapped(ctx, S:t("err.workspace_missing.action"))
    else
      local action = view.draw(ctx, sess)
      if action == "fetch" then sess:start_fetch()
      elseif action == "send" then sess:start_send()
      elseif action == "undo" then sess:undo() end
      if sess:running() then sess:step() end
    end
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end
reaper.defer(loop)
