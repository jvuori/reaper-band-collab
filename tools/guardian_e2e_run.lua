-- Runs inside a REAPER that was STARTED with the guardian's start-up block installed. It does nothing
-- to start the guardian: it only watches for the guardian's heartbeat, then opens the master as the
-- member would. Env: E2E_MASTER (project to open), E2E_DIR (signal and result files).
local master = assert(os.getenv("E2E_MASTER"))
local dir = assert(os.getenv("E2E_DIR"))
local t0 = reaper.time_precise()
local beat_at, opened_at

local function exists(p) local f = io.open(p, "r"); if f then f:close(); return true end end
local function finish()
  local f = io.open(dir .. "/result.txt", "w")
  f:write("guardian_started_by_itself=", tostring(beat_at ~= nil), "\n")
  f:write("seconds_until_heartbeat=", beat_at and string.format("%.1f", beat_at) or "never", "\n")
  f:write("guardian_error=", (reaper.GetExtState("bandcollab", "guardian_error"):gsub("\n", " / ")), "\n")
  f:close()
  os.exit(0, true)
end

local function loop()
  local now = reaper.time_precise() - t0
  if not beat_at and reaper.GetExtState("bandcollab", "guardian_beat") ~= "" then beat_at = now end
  if beat_at and not opened_at and now > beat_at + 1.5 then
    reaper.Main_OnCommand(40859, 0)
    reaper.Main_openProject("noprompt:" .. master)
    opened_at = now
    local f = io.open(dir .. "/opened", "w"); f:write("ok\n"); f:close()
  end
  if exists(dir .. "/stop") or now > 40 then finish() end
  reaper.defer(loop)
end
reaper.defer(loop)
