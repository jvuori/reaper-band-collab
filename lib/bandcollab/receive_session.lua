-- The logic behind the "receive a rehearsal" panel: rows for the songs found, the producer's
-- choices, and a receive job that runs in slices so REAPER stays responsive. No drawing here.
local receive = require("bandcollab.receive")
local messages = require("bandcollab.messages")
local bandfile = require("bandcollab.bandfile")
local cycles = require("bandcollab.cycles")

local M = {}

local Session = {}
Session.__index = Session

-- new(fs, band, band_folder, S, member) -> session | nil, code
-- Only the producer receives rehearsals.
function M.new(fs, band, band_folder, S, member, env)
  if member ~= band.producer then return nil, "not_producer" end
  local ctx, code = receive.context(fs, band, band_folder)
  if not ctx then return nil, code end
  local libs = bandfile.libraries(band)
  return setmetatable({
    fs = fs, band = band, ctx = ctx, S = S, rows = {}, results = {},
    library = libs[1].id, cycle = os.date("%Y-%m-%d"), job = nil, progress = "", env = env or {},
  }, Session)
end

local function describe(S, cand)
  local id = cand.identity
  if not cand.inspection.ok then
    local parts = {}
    for _, p in ipairs(cand.inspection.problems) do parts[#parts + 1] = messages.from_problem(S, p).what end
    return { kind = "problem", text = table.concat(parts, " ") }
  end
  if id.state == "already_received" then
    return { kind = "already", text = messages.get(S, "already_received", { detail = id.entry.title }).what }
  elseif id.state == "same" then
    return { kind = "already", text = messages.get(S, "already_registered", { detail = id.entry.title }).what }
  elseif id.state == "copy" then
    return { kind = "copy", text = S:t("ui.receive.song_copy_question", { title = id.entry.title }) }
  end
  return { kind = "ok", text = S:t("ui.receive.song_ok") }
end

-- scan(staging [, keep_results]) -> number of songs found
-- A new scan clears the results of the previous receive, unless it is a refresh after one.
function Session:scan(staging, keep_results)
  self.rows = {}
  if not keep_results then self.results = {} end
  for _, cand in ipairs(receive.candidates(self.ctx, staging)) do
    self.rows[#self.rows + 1] = { cand = cand, selected = cand.selected, title = cand.title, decision = nil, status = describe(self.S, cand) }
  end
  return #self.rows
end

-- can_select(row) -> whether the song may be received right now
function Session:can_select(row)
  local c = row.cand
  if not c.inspection.ok then return false end
  local state = c.identity.state
  if state == "new" or state == "moved" then return true end
  return state == "copy" and row.decision == "copy"
end

-- decide(row, "copy" | "skip"): the answer to "is this a copy?"
function Session:decide(row, decision)
  row.decision = decision
  row.selected = decision == "copy"
end

function Session:ready_rows()
  local out = {}
  for _, row in ipairs(self.rows) do
    if row.selected and self:can_select(row) then out[#out + 1] = row end
  end
  return out
end

-- start(): begin receiving the selected songs; drive it with step() until it returns true.
function Session:start()
  local rows = self:ready_rows()
  self.results = {}
  self.job = coroutine.create(function()
    for _, row in ipairs(rows) do
      local entry, code, detail = receive.import(self.ctx, row.cand, {
        library = self.library, cycle = self.cycle, title = row.title, copy = row.decision == "copy",
        master_prefix = self.S:t("master.file_prefix"),
        yield = function(_, file)
          self.progress = self.S:t("ui.receive.progress", { file = tostring(file):match("[^/\\]*$") })
          coroutine.yield()
        end,
      })
      if entry then
        if self.env.mark_master then -- the visible banner inside the master project (needs REAPER)
          local file = self.ctx.band_folder .. "/" .. entry.path .. "/" .. self.S:t("master.file_prefix") .. "_" .. entry.slug .. ".rpp"
          pcall(self.env.mark_master, self.fs, file, self.S:t("master.marker"))
        end
        self.results[#self.results + 1] = { ok = true, title = row.title, text = self.S:t("ui.receive.received", { title = row.title }), entry = entry }
      else
        local detail_text = type(detail) == "table" and (detail[1] and detail[1].path) or detail
        local msg = messages.get(self.S, code, { detail = detail_text })
        self.results[#self.results + 1] = { ok = false, title = row.title, text = row.title .. ": " .. msg.text }
      end
      coroutine.yield()
    end
  end)
  self.progress = ""
  return #rows
end

-- step() -> true when everything has been received (or nothing was started)
function Session:step()
  if not self.job then return true end
  if coroutine.status(self.job) == "dead" then self.job = nil; return true end
  local ok, err = coroutine.resume(self.job)
  if not ok then
    self.job = nil
    self.results[#self.results + 1] = { ok = false, title = "", text = tostring(err) }
    return true
  end
  if coroutine.status(self.job) == "dead" then self.job = nil; return true end
  return false
end

function Session:running() return self.job ~= nil end

-- after a receive the registry has changed: look at the folder again
function Session:refresh(staging) return self:scan(staging, true) end

-- libraries() -> list, and cycles_of(library id) -> list of { cycle =, state = }
function Session:libraries() return bandfile.libraries(self.band) end

function Session:cycles_of(library_id)
  local lib = bandfile.library(self.band, library_id)
  if not lib or lib.kind ~= "dated" then return {} end
  return cycles.list(self.fs, self.band, self.ctx.band_folder, lib)
end

-- close_cycle(library_id, date) -> true | nil, message
function Session:close_cycle(library_id, date)
  local lib = bandfile.library(self.band, library_id)
  local ok, code, detail = cycles.close(self.fs, self.band, self.ctx.band_folder, lib, date)
  if ok then return true end
  return nil, messages.get(self.S, code, { detail = detail or date }).text
end

return M
