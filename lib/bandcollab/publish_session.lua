-- The logic behind the "publish a version" panel: what the open project is, whether it can be
-- published, and a publish job that runs in slices so REAPER stays responsive. No drawing here.
-- The parts that touch REAPER (which project is open, is it saved) and the publisher itself are
-- injected, so the session can be tested without REAPER.
local songfile = require("bandcollab.songfile")
local revisions = require("bandcollab.revisions")
local cycles = require("bandcollab.cycles")
local messages = require("bandcollab.messages")
local bandfile = require("bandcollab.bandfile")
local path = require("bandcollab.path")

local M = {}

-- The default environment: the active REAPER project and the real publisher.
function M.reaper_env()
  local publisher = require("bandcollab.publisher")
  return {
    project = function() return (reaper.EnumProjects(-1)) end,
    file = publisher.project_file,
    dirty = function(proj) return reaper.IsProjectDirty(proj) ~= 0 end,
    publish = publisher.publish,
  }
end

local Session = {}
Session.__index = Session

-- new(fs, band, band_folder, S, member [, env]) -> session | nil, code   (only the producer publishes)
function M.new(fs, band, band_folder, S, member, env)
  if member ~= band.producer then return nil, "not_producer" end
  return setmetatable({
    fs = fs, band = band, band_folder = band_folder, S = S, env = env or M.reaper_env(),
    status = { kind = "unknown" }, note = { summary = "", body = "" }, tasks = {},
    job = nil, progress = "", result = nil,
  }, Session)
end

-- refresh() -> status: what the open project is right now
--   { kind = "no_song" }                  not received into the band folder (or not a saved project)
--   { kind = "unsaved", song = }          has unsaved changes
--   { kind = "ready", song =, next =, last = }
function Session:refresh()
  local proj = self.env.project()
  local file = proj and self.env.file(proj)
  if not file then self.status = { kind = "no_song" }; return self.status end
  local song = songfile.read(self.fs, path.dirname(file))
  if not song then self.status = { kind = "no_song" }; return self.status end
  if self.env.dirty(proj) then self.status = { kind = "unsaved", song = song }; return self.status end

  local library = bandfile.library(self.band, song.library)
  local pub_dir = cycles.dir(self.band, self.band_folder, "publications", song.library,
    library and library.kind == "dated" and song.cycle or nil) .. "/" .. song.slug
  local last = revisions.latest(self.fs, pub_dir)
  local existing = revisions.list(self.fs, pub_dir)
  local next_number = (existing[#existing] and (existing[#existing].complete and existing[#existing].number + 1 or existing[#existing].number)) or 1
  self.status = { kind = "ready", song = song, proj = proj, pub_dir = pub_dir, next = next_number, last = last and last.number or nil }
  return self.status
end

-- add_task(who, text) / remove_task(index): requests for members, shown in the log
function Session:add_task(who, text) self.tasks[#self.tasks + 1] = { who = who or "", text = text or "" } end
function Session:remove_task(index) table.remove(self.tasks, index) end

local function clean_tasks(tasks)
  local out = {}
  for _, task in ipairs(tasks) do
    local text = (task.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= "" then out[#out + 1] = { who = task.who, text = text } end
  end
  return out
end

-- start() -> true | nil, code: begin publishing; drive with step() until it returns true
function Session:start()
  local status = self:refresh()
  if status.kind ~= "ready" then return nil, status.kind == "unsaved" and "project_unsaved" or "not_a_song" end
  local note = { summary = (self.note.summary or ""):gsub("^%s+", ""):gsub("%s+$", ""), body = (self.note.body or ""):gsub("^%s+", ""):gsub("%s+$", "") }
  local tasks = clean_tasks(self.tasks)
  self.result, self.progress = nil, ""
  self.job = coroutine.create(function()
    local result, code, detail = self.env.publish(self.fs, self.band, self.band_folder, status.proj, self.S, {
      note = note, tasks = tasks,
      step = function(text) self.progress = text; coroutine.yield() end,
      yield = function() coroutine.yield() end,
    })
    if result then
      self.result = { ok = true, revision = result.revision, structure = result.structure, text = self.S:t("ui.publish.done", { n = result.revision }) }
      self.note, self.tasks = { summary = "", body = "" }, {}
    else
      self.result = { ok = false, code = code, text = messages.get(self.S, code, { detail = type(detail) == "string" and detail or "" }).text }
    end
  end)
  return true
end

-- step() -> true when finished (or when nothing is running)
function Session:step()
  if not self.job then return true end
  local ok, err = coroutine.resume(self.job)
  if not ok then
    self.job = nil
    self.result = { ok = false, text = tostring(err) }
    return true
  end
  if coroutine.status(self.job) == "dead" then self.job = nil; return true end
  return false
end

function Session:running() return self.job ~= nil end

return M
