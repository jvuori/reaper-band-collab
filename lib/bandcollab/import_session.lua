-- The logic behind the producer's "Ehdotukset" panel: the inbox, reviewing one proposal against
-- the open master (a preview that writes nothing), editing the note for the log, taking it in,
-- and undoing the last import. No drawing here; the operations are injected so it can be tested
-- without REAPER.
local messages = require("bandcollab.messages")
local changelog = require("bandcollab.changelog")

local M = {}

function M.reaper_env()
  local inbox = require("bandcollab.inbox")
  local importer = require("bandcollab.importer")
  return {
    inbox = inbox.list,
    master = function(fs) return importer.identify_master(fs, (reaper.EnumProjects(-1))) end,
    preview = importer.preview, import = importer.import, undo = importer.undo_import, can_undo = importer.can_undo,
    publications_dir = importer.publications_dir,
  }
end

local Session = {}
Session.__index = Session

-- new(fs, band, band_folder, S, member [, env]) -> session | nil, "not_producer"
function M.new(fs, band, band_folder, S, member, env)
  if member ~= band.producer then return nil, "not_producer" end
  return setmetatable({
    fs = fs, band = band, band_folder = band_folder, S = S, env = env or M.reaper_env(),
    inbox = { pending = {}, accepted = {}, arriving = {} }, master = nil, undo_delivery = nil,
    selected = nil, preview = nil, problem = nil, note = { summary = "", body = "" },
    job = nil, progress = "", result = nil,
  }, Session)
end

function Session:refresh()
  self.inbox = self.env.inbox(self.fs, self.band, self.band_folder)
  self.master = self.env.master(self.fs)
  self.undo_delivery = self.master and self.env.can_undo(self.fs, self.master) or nil
  return #self.inbox.pending
end

-- review(entry): look at a proposal against the open master. Nothing is written.
function Session:review(entry)
  self.selected, self.preview, self.problem, self.result = entry, nil, nil, nil
  if not self.master or (entry.song_id and self.master.song.id ~= entry.song_id) then
    self.problem = { code = "open_master", text = self.S:t("ui.import.open_master") }
    return false
  end
  local pre, code, detail = self.env.preview(self.fs, self.band, self.band_folder, self.master, entry)
  if not pre then
    local d = type(detail) == "string" and detail or ""
    self.problem = { code = code, text = messages.get(self.S, code, { detail = d, path = d }).text }
    return false
  end
  self.preview = pre
  self.note = { summary = (pre.note and pre.note.summary) or "", body = (pre.note and pre.note.body) or "" }
  return true
end

-- cancel(): drop the review; nothing was changed
function Session:cancel() self.selected, self.preview, self.problem = nil, nil, nil end

-- lines() -> the preview as plain text lines (what will be replaced, versions, timing)
function Session:lines()
  local out = {}
  local pre, S = self.preview, self.S
  if not pre then return out end
  for _, f in ipairs(pre.folders) do
    if f.ignored then out[#out + 1] = S:t("ui.import.ignored", { label = f.label })
    elseif f.before then
      out[#out + 1] = S:t("ui.import.replaced", { label = f.label, b_tracks = f.before.tracks, b_items = f.before.items, a_tracks = f.after.tracks, a_items = f.after.items })
    else
      out[#out + 1] = S:t("ui.import.added", { label = f.label, a_tracks = f.after.tracks, a_items = f.after.items })
    end
  end
  out[#out + 1] = S:t("ui.import.versions", { base = pre.base or "?", current = pre.current or "?" })
  local mt, pt = pre.timing.master, pre.timing.proposal
  if pt and mt then
    out[#out + 1] = S:t("ui.import.tempo", { m = string.format("%.1f", mt.bpm), p = string.format("%.1f", pt.bpm) })
    out[#out + 1] = S:t("ui.import.length", { m = changelog.clock(mt.length), p = changelog.clock(pt.length) })
  end
  return out
end

-- warnings() -> { { severity =, text = } } in plain words
function Session:warnings()
  local out = {}
  for _, w in ipairs(self.preview and self.preview.warnings or {}) do
    local msg = messages.get(self.S, w.code, w.vars or { detail = w.detail })
    out[#out + 1] = { severity = w.severity, text = msg.what .. " " .. msg.action }
  end
  return out
end

local function fail(self, code, detail)
  local d = type(detail) == "string" and detail or ""
  self.result = { ok = false, code = code, text = messages.get(self.S, code, { detail = d, path = d }).text }
end

-- start_import(): take the reviewed proposal into the master; drive with step()
function Session:start_import()
  if not self.preview or not self.selected then return false end
  local entry = self.selected
  self.result, self.progress = nil, ""
  self.job = coroutine.create(function()
    local res, code, detail = self.env.import(self.fs, self.band, self.band_folder, self.master, entry, self.S, {
      note = { summary = self.note.summary, body = self.note.body },
      yield = function(_, file)
        self.progress = self.S:t("ui.import.working", { step = tostring(file or ""):match("[^/\\]*$") })
        coroutine.yield()
      end,
    })
    if not res then return fail(self, code, detail) end
    self.result = { ok = true, text = self.S:t("ui.import.imported"), delivery = res.delivery }
    self.selected, self.preview = nil, nil
  end)
  return true
end

-- undo() -> true | false: reverse the last import
function Session:undo()
  self.result = nil
  local pub_dir = self.env.publications_dir(self.band, self.band_folder, self.master)
  local res, code, detail = self.env.undo(self.fs, self.band, self.band_folder, self.master, pub_dir, self.S)
  if not res then fail(self, code, detail); return false end
  self.result = { ok = true, text = self.S:t("ui.import.undone") }
  self.selected, self.preview = nil, nil
  self:refresh()
  return true
end

function Session:step()
  if not self.job then return true end
  local ok, err = coroutine.resume(self.job)
  if not ok then self.job = nil; self.result = { ok = false, text = tostring(err) }; return true end
  if coroutine.status(self.job) == "dead" then self.job = nil; self:refresh(); return true end
  return false
end

function Session:running() return self.job ~= nil end

-- row_text(entry) / tag(entry): the inbox rows
function Session:row_text(entry)
  return self.S:t("ui.import.row", { member = entry.member_name, title = entry.title, time = entry.sent })
end

function Session:tag(entry)
  return entry.outdated and self.S:t("ui.import.outdated_tag", { n = entry.base }) or nil
end

return M
