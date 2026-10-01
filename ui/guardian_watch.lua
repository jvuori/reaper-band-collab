-- @description Band guardian: warns when you open a project that is not yours to work in
-- @version 0.0.1
-- Runs in the background (started with REAPER by the start-up block). It only ever speaks about
-- the band's own projects; an ordinary project never gets a message.
local dir = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
local boot = dofile(dir .. "/bootstrap.lua")(dir)

if not reaper.APIExists("ImGui_CreateContext") then return end -- no way to show anything: stay quiet

-- one guardian per REAPER session (the start-up block and a manual start must not both run)
local last = tonumber(reaper.GetExtState("bandcollab", "guardian_beat"))
if last and reaper.time_precise() - last < 5 then return end
reaper.SetExtState("bandcollab", "guardian_beat", tostring(reaper.time_precise()), false)

local firstrun = require("bandcollab.firstrun")
local localsettings = require("bandcollab.localsettings")
local guardian_runtime = require("bandcollab.guardian_runtime")
local guardian_reaper = require("bandcollab.guardian_reaper")
local fs = require("bandcollab.fs_std")
local view = require("guardian_view")

local settings = localsettings.new(localsettings.reaper_backend())
local S = boot.strings("fi")
-- ReaImGui throws away a context that has not been used for a while, and the guardian draws only when
-- there is something to say, so the context is made when needed and made again if it was discarded.
local ctx
local function context()
  if not ctx or not reaper.ImGui_ValidatePtr(ctx, "ImGui_Context*") then ctx = reaper.ImGui_CreateContext("bandcollab_guardian") end
  return ctx
end
local runtime, configured_for
local pending = {}
local next_look, next_beat, next_setup = 0, 0, 0

local function setup()
  local band, member = firstrun.current(settings, fs)
  if not band then runtime, configured_for = nil, nil; return end -- this machine is not set up (yet): nothing to guard
  local identity = settings:band_folder() .. "|" .. member
  if identity ~= configured_for then
    configured_for = identity
    runtime = guardian_runtime.new(fs, band, settings:band_folder(), member, function() return os.date("%Y-%m-%dT%H:%M:%S") end)
    S.lang = band.language
  end
end

local function handle(alert, action)
  if action == "close" and reaper.ValidatePtr(alert.handle, "ReaProject*") then
    reaper.SelectProjectInstance(alert.handle)
    reaper.Main_OnCommand(40860, 0) -- File: Close current project tab (REAPER asks first if there is unsaved work)
  elseif action == "sync" then
    pcall(dofile, dir .. "/synkronoi.lua")
  elseif action == "open_right" then
    for _, w in ipairs(alert.warnings) do
      if w.code == "misplaced" and w.vars and w.vars.where and fs.exists(w.vars.where) then
        reaper.Main_OnCommand(40859, 0)
        reaper.Main_openProject("noprompt:" .. w.vars.where)
      end
    end
  end
end

local errors = 0

-- One look, with everything that can go wrong inside. An unexpected error must never reach the
-- person as a "ReaScript Error" window: it is recorded (the e2e test and a helper can read it) and
-- the guardian carries on; after repeated failures it stops quietly.
local function step()
  local now = reaper.time_precise()
  if now >= next_beat then reaper.SetExtState("bandcollab", "guardian_beat", tostring(now), false); next_beat = now + 1 end
  if now >= next_setup then setup(); next_setup = now + 3 end
  if runtime and now >= next_look then
    next_look = now + 0.4
    for _, alert in ipairs(runtime:scan(guardian_reaper.projects())) do pending[#pending + 1] = alert end
  end
  local alert = pending[1]
  if alert then
    local c = context()
    reaper.ImGui_SetNextWindowSizeConstraints(c, 540, 120, 900, 700) -- auto-resize alone would shrink to a sliver
    local visible, open = reaper.ImGui_Begin(c, S:t("guardian.title"), true, reaper.ImGui_WindowFlags_AlwaysAutoResize())
    if visible then
      local action = view.draw(c, alert, S)
      if action then handle(alert, action); table.remove(pending, 1) end
      reaper.ImGui_End(c)
    end
    if not open then table.remove(pending, 1) end
  end
end

local function loop()
  local ok, err = xpcall(step, debug.traceback)
  if not ok then
    errors = errors + 1
    reaper.SetExtState("bandcollab", "guardian_error", tostring(err), false)
    if errors >= 5 then return end -- give up quietly rather than nag
    pending = {}
  end
  reaper.defer(loop)
end
reaper.defer(loop)
