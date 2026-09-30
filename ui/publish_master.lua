-- @description Publish a version (producer): render stems and a reference mix of the open song
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
local publish_session = require("bandcollab.publish_session")
local fs = require("bandcollab.fs_std")
local view = require("publish_view")

local S = boot.strings("fi")
local settings = localsettings.new(localsettings.reaper_backend())
local band, member_or_code = firstrun.current(settings, fs)
if not band then
  reaper.ShowMessageBox(messages.get(S, member_or_code or "firstrun_needed").text, "Band Collab", 0)
  return
end
S.lang = band.language

local sess, code = publish_session.new(fs, band, settings:band_folder(), S, member_or_code)
if not sess then
  reaper.ShowMessageBox(messages.get(S, code).text, "Band Collab", 0)
  return
end

local ctx = reaper.ImGui_CreateContext("bandcollab_publish")
local frames_since_refresh = 0

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 640, 520, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, S:t("ui.publish.title"), true)
  if visible then
    -- look at the open project again now and then (the user may switch projects or save)
    frames_since_refresh = frames_since_refresh + 1
    if not sess:running() and frames_since_refresh >= 30 then sess:refresh(); frames_since_refresh = 0 end
    if sess.status.kind == "unknown" then sess:refresh() end

    local action = view.draw(ctx, sess, S)
    if action == "publish" then
      local ok, err = sess:start()
      if not ok then sess.result = { ok = false, text = messages.get(S, err).text } end
    end
    if sess:running() then
      if sess:step() then sess:refresh() end
    end
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end
reaper.defer(loop)
