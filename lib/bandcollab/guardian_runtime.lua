-- What the guardian does on each look at the open projects: for every project that has just been
-- opened, check it, keep only the warnings not shown yet for that open, log the strong ones, and
-- hand back the alerts to display. REAPER-agnostic: the open projects are passed in.
local guardian = require("bandcollab.guardian")

local M = {}

local Runtime = {}
Runtime.__index = Runtime

-- new(fs, band, band_folder, member [, now]) -> runtime; now() returns an ISO time (default: a plain clock)
function M.new(fs, band, band_folder, member, now)
  return setmetatable({
    fs = fs, band = band, band_folder = band_folder, member = member,
    tracker = guardian.new_tracker(), now = now or function() return os.date("!%Y-%m-%dT%H:%M:%SZ") end,
  }, Runtime)
end

local ORDER = { strong = 1, warning = 2, soft = 3 }

-- scan(open) -> alerts. open = list of { handle =, file =, marker_kind = } (the open project tabs)
-- alert = { handle =, file =, warnings = { {code, severity, vars}... } } sorted strongest first
function Runtime:scan(open)
  local live, alerts = {}, {}
  for _, p in ipairs(open) do
    live[guardian.key(p.handle, p.file)] = true
    if p.file and p.file ~= "" and self.tracker:is_new_open(p.handle, p.file) then
      local result = guardian.check(self.fs, self.band, self.band_folder, self.member, { file = p.file, marker_kind = p.marker_kind })
      local fresh = {}
      for _, w in ipairs(result.warnings) do
        if self.tracker:should_show(p.handle, p.file, w.code) then
          fresh[#fresh + 1] = w
          if w.code == "master" then guardian.log_event(self.fs, self.band, self.band_folder, self.member, w.code, p.file, self.now()) end
        end
      end
      if #fresh > 0 then
        table.sort(fresh, function(a, b) return ORDER[a.severity] < ORDER[b.severity] end)
        alerts[#alerts + 1] = { handle = p.handle, file = p.file, warnings = fresh }
      end
    end
  end
  self.tracker:forget_closed(live)
  return alerts
end

return M
