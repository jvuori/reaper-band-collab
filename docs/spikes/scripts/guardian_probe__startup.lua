local out = io.open((os.getenv("SPIKE_OUT_DIR") or ".") .. "/guardian_probe.out", "w")
local function w(...) out:write(string.format(...), "\n"); out:flush() end
local last_key, ticks, stage = nil, 0, 0
local function key()
  local proj, path = reaper.EnumProjects(-1, "")
  return tostring(proj) .. "|" .. tostring(path)
end
local function loop()
  ticks = ticks + 1
  local k = key()
  if k ~= last_key then
    local _, p = reaper.EnumProjects(-1, "")
    local cnt = 0; while reaper.EnumProjects(cnt) do cnt = cnt + 1 end
    w("tick %d: active project changed -> path=%q tabs=%d", ticks, p, cnt)
    last_key = k
  end
  if ticks == 20 then stage = 1; reaper.Main_openProject(os.getenv("SPIKE_PROJ_A")) end
  if ticks == 60 then stage = 2; reaper.Main_openProject("noprompt:" .. os.getenv("SPIKE_PROJ_B")) end
  if ticks == 100 then reaper.SelectProjectInstance(reaper.EnumProjects(1)) end
  if ticks == 140 then w("loop still running at tick %d", ticks); out:close(); reaper.Main_OnCommand(40004, 0); return end
  reaper.defer(loop)
end
reaper.defer(loop)
