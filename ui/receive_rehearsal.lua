-- @description Receive a rehearsal (producer): register songs copied from the recording computer
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
local receive_session = require("bandcollab.receive_session")
local fs = require("bandcollab.fs_std")
local view = require("receive_view")

local S = boot.strings("fi")
local settings = localsettings.new(localsettings.reaper_backend())
local band, member_or_code = firstrun.current(settings, fs)
if not band then
  local msg = messages.get(S, member_or_code or "firstrun_needed")
  reaper.ShowMessageBox(msg.text, "Band Collab", 0)
  return
end
S.lang = band.language

local master_marker = require("bandcollab.master_marker")
local sess, code = receive_session.new(fs, band, settings:band_folder(), S, member_or_code, { mark_master = master_marker.ensure })
if not sess then
  reaper.ShowMessageBox(messages.get(S, code).text, "Band Collab", 0)
  return
end

local ui = { staging = "", scanned = false }
local ctx = reaper.ImGui_CreateContext("bandcollab_receive")

local function scan()
  sess:scan(ui.staging)
  ui.scanned = true
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 720, 520, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, S:t("ui.receive.title"), true)
  if visible then
    local action = view.draw(ctx, sess, ui)
    if action == "pick" then
      local ok, file = reaper.GetUserFileNameForRead("", S:t("ui.receive.pick_title"), "")
      if ok then ui.staging = firstrun.folder_from_file(file); scan() end
    elseif action == "scan" then
      scan()
    elseif action == "start" then
      sess:start()
    end
    if sess:running() then
      if sess:step() then sess:refresh(ui.staging) end -- look again; results stay visible
    end
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end
reaper.defer(loop)
