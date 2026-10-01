-- The logic behind the "Synkronoi" panel: which of the two directions make sense right now, the
-- ordered two-step flow, what must be confirmed before sending, and the jobs that run in slices so
-- REAPER stays responsive. No drawing here. The operations are injected, so it can be tested
-- without REAPER.
local messages = require("bandcollab.messages")

local M = {}

-- The real operations (need REAPER).
function M.reaper_env()
  local sync = require("bandcollab.workspace_sync")
  local projects = require("bandcollab.projects")
  return {
    status = sync.status, fetch = sync.fetch, undo = sync.undo_fetch, can_undo = sync.can_undo,
    preflight = sync.preflight, send = sync.send, fix_orphans = sync.fix_orphans,
    save = function(ws) projects.save_bound(ws.proj) end,
  }
end

local Session = {}
Session.__index = Session

-- new(fs, band, band_folder, S, ws [, env]) -> session; ws is an open workspace (workspace_sync.identify)
function M.new(fs, band, band_folder, S, ws, env)
  return setmetatable({
    fs = fs, band = band, band_folder = band_folder, S = S, ws = ws, env = env or M.reaper_env(),
    status = nil, undo_from = nil, note = { summary = "", body = "" }, ack = {}, pre = nil,
    job = nil, progress = "", result = nil,
  }, Session)
end

function Session:refresh()
  self.status = self.env.status(self.fs, self.band, self.band_folder, self.ws)
  self.undo_from = self.env.can_undo(self.fs, self.ws)
  return self.status
end

-- cards() -> what the panel shows. The direction is never chosen for the member: it only says
-- which of the two are meaningful. With changes on both sides, fetching comes first and proposing
-- waits ("propose_waits") until the fetch is done.
function Session:cards()
  local st = self.status
  local kind = st.sync.kind
  return {
    nothing = kind == "none" and not st.arriving,
    arriving = st.arriving,
    fetch = kind == "down" or kind == "both",
    propose = (kind == "up" or kind == "both") and not st.closed,
    propose_waits = kind == "both",
    closed = st.closed,
  }
end

-- proposal_text() -> the status line about the latest proposal, or nil
function Session:proposal_text()
  local p = self.status and self.status.proposal
  if not p then return nil end
  return self.S:t(p.status == "accepted" and "ui.sync.proposal_accepted" or "ui.sync.proposal_pending", { time = p.sent })
end

local function trimmed(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function slice_progress(self)
  return function(_, file)
    self.progress = self.S:t("ui.sync.working", { step = tostring(file or ""):match("[^/\\]*$") })
    coroutine.yield()
  end
end

local function fail(self, code, detail)
  local d = type(detail) == "string" and detail or ""
  -- some messages name a {path} (the file that has not fully arrived), others a {detail}
  self.result = { ok = false, code = code, text = messages.get(self.S, code, { detail = d, path = d }).text }
end

-- start_fetch(): "Hae pääversio"; drive with step() until it returns true
function Session:start_fetch()
  self.result, self.progress = nil, ""
  self.job = coroutine.create(function()
    local res, code, detail = self.env.fetch(self.fs, self.band, self.band_folder, self.ws, { yield = slice_progress(self) })
    if not res then return fail(self, code, detail) end
    local text = self.S:t("ui.sync.fetched", { n = res.to })
    local warning
    if res.structure and res.structure.changed then
      local names = {}
      for _, r in ipairs(res.structure.reasons) do names[#names + 1] = self.S:t("log.reason_" .. r) end
      warning = self.S:t("ui.sync.structure_warning", { reasons = table.concat(names, ", ") })
    end
    self.result = { ok = true, text = text, warning = warning, structure = res.structure }
  end)
end

-- undo() -> true | false; synchronous
function Session:undo()
  self.result = nil
  local res, code, detail = self.env.undo(self.fs, self.ws)
  if not res then fail(self, code, detail); return false end
  self.result = { ok = true, text = self.S:t("ui.sync.undone") }
  self:refresh()
  return true
end

-- problems() -> the preflight's findings as texts: { code =, severity =, text =, fix =, confirmed = bool }
function Session:problems()
  local out = {}
  for _, p in ipairs(self.pre and self.pre.problems or {}) do
    local msg = messages.get(self.S, p.code, { detail = p.detail })
    out[#out + 1] = { code = p.code, severity = p.severity, text = msg.what .. " " .. msg.action, fix = p.fix, confirmed = self.ack[p.code] == true }
  end
  return out
end

function Session:acknowledge(code, yes) self.ack[code] = yes and true or nil end

-- check() -> true when everything is in order to send (blocking problems fixed, warnings confirmed)
function Session:check()
  self.pre = self.env.preflight(self.fs, self.band, self.band_folder, self.ws)
  if self.pre.blocking then fail(self, "preflight_failed"); return false end
  for _, code in ipairs(self.pre.warnings) do
    if not self.ack[code] then fail(self, "preflight_needs_ack"); return false end
  end
  self.result = nil
  return true
end

-- apply_fix(problem): carries out the fix a problem offers (moving stray tracks into the member's folder)
function Session:apply_fix(problem)
  if problem.fix == "move_orphans" then
    local moved, code = self.env.fix_orphans(self.ws.proj, self.band, self.ws.state.member)
    if not moved then fail(self, code or "preflight_failed"); return false end
    self.env.save(self.ws) -- moving tracks changes the project, and a proposal is made from a saved one
    self.pre = self.env.preflight(self.fs, self.band, self.band_folder, self.ws)
    self.result = nil
    return true
  end
  return false
end

-- start_send(): "Ehdota"; nothing starts unless check() passes
function Session:start_send()
  if not self:check() then return false end
  self.progress = ""
  self.job = coroutine.create(function()
    local res, code, detail = self.env.send(self.fs, self.band, self.band_folder, self.ws, {
      note = { summary = trimmed(self.note.summary), body = trimmed(self.note.body) },
      acknowledged = self.ack, yield = slice_progress(self),
    })
    if not res then return fail(self, code, detail) end
    self.note, self.ack, self.pre = { summary = "", body = "" }, {}, nil
    self.result = { ok = true, text = self.S:t("ui.sync.sent"), delivery = res.id }
  end)
  return true
end

-- step() -> true when finished (or nothing is running); refreshes the status when a job ends
function Session:step()
  if not self.job then return true end
  local ok, err = coroutine.resume(self.job)
  if not ok then
    self.job = nil
    self.result = { ok = false, text = tostring(err) }
    return true
  end
  if coroutine.status(self.job) == "dead" then
    self.job = nil
    self:refresh()
    return true
  end
  return false
end

function Session:running() return self.job ~= nil end

return M
