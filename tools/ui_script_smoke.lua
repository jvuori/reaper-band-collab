-- Runs a real UI script (ui/*.lua) inside REAPER for a number of frames and reports errors.
-- A failure inside the script's defer loop would normally open a blocking dialog; here the
-- loop is wrapped so errors are recorded instead.
-- Env: BANDCOLLAB_ROOT, SMOKE_SCRIPT (path), SMOKE_OUT (result file), SMOKE_FRAMES (default 60)
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

local script = assert(os.getenv("SMOKE_SCRIPT"), "SMOKE_SCRIPT not set")
local out_path = assert(os.getenv("SMOKE_OUT"), "SMOKE_OUT not set")
local frames_wanted = tonumber(os.getenv("SMOKE_FRAMES") or "60")

local errors, frames, pending = {}, 0, nil
local real_defer = reaper.defer
reaper.defer = function(fn) pending = fn end -- capture the script's loop instead of scheduling it

local function report()
  local f = io.open(out_path, "w")
  f:write(string.format("script=%s\nframes=%d\nerrors=%d\n", script, frames, #errors))
  for _, e in ipairs(errors) do f:write(e, "\n") end
  f:close()
  safe_quit()
end

local ok, err = pcall(dofile, script)
if not ok then errors[#errors + 1] = "load: " .. tostring(err); report(); return end

local function tick()
  if not pending then errors[#errors + 1] = "script stopped scheduling frames after " .. frames; report(); return end
  local fn = pending
  pending = nil
  local fok, ferr = pcall(fn)
  frames = frames + 1
  if not fok then errors[#errors + 1] = "frame " .. frames .. ": " .. tostring(ferr); report(); return end
  if frames >= frames_wanted then report(); return end
  real_defer(tick)
end
real_defer(tick)
