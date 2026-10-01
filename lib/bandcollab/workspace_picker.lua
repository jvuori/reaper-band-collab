-- The logic behind the "Luo oma työtila" panel: the songs a member can work on, whether they
-- already have a workspace for each, and creating or opening one. No drawing here; the operations
-- are injected so this can be tested without REAPER.
local songs_list = require("bandcollab.songs_list")
local wm = require("bandcollab.workspace_model")
local bandfile = require("bandcollab.bandfile")
local messages = require("bandcollab.messages")

local M = {}

function M.reaper_env()
  local workspace = require("bandcollab.workspace")
  return {
    create = workspace.create,
    open = function(file) reaper.Main_OnCommand(40859, 0); reaper.Main_openProject("noprompt:" .. file) end,
  }
end

local Session = {}
Session.__index = Session

-- new(fs, band, band_folder, S, member_id [, env]) -> session
function M.new(fs, band, band_folder, S, member_id, env)
  return setmetatable({
    fs = fs, band = band, band_folder = band_folder, S = S, member = member_id, env = env or M.reaper_env(),
    songs = {}, arriving = {}, job = nil, progress = "", result = nil,
  }, Session)
end

-- refresh(): look at the publications again. Each song gets `workspace` (the file of the member's
-- workspace when they already have one) and keeps `closed` from the listing.
function Session:refresh()
  local found = songs_list.list(self.fs, self.band, self.band_folder)
  self.songs, self.arriving = found.songs, found.arriving
  for _, song in ipairs(self.songs) do
    local dir = wm.dir(self.band, self.band_folder, self.member, song)
    song.workspace = wm.read_state(self.fs, dir) and wm.project_file(dir, song.slug) or nil
  end
  return #self.songs
end

-- empty_message() -> what to say when there is nothing to offer, or nil
function Session:empty_message()
  if #self.songs > 0 then return nil end
  return self.S:t(#self.arriving > 0 and "ui.picker.arriving" or "ui.picker.nothing")
end

-- who() -> "You are Eero (Rummut, Koskettimet)."
function Session:who()
  for _, m in ipairs(self.band.members) do
    if m.id == self.member then
      local labels = {}
      for _, r in ipairs(bandfile.roles_of(self.band, m.id)) do labels[#labels + 1] = r.label end
      return self.S:t("ui.picker.you", { name = m.name, roles = table.concat(labels, ", ") })
    end
  end
  return ""
end

-- can_create(song): a song without a workspace of the member's, in a cycle that is still open
function Session:can_create(song) return song.workspace == nil and not song.closed end

-- start_create(song): make the workspace in slices; drive with step()
function Session:start_create(song)
  self.result, self.progress = nil, ""
  self.job = coroutine.create(function()
    local ws, code, detail = self.env.create(self.fs, self.band, self.band_folder, self.member, song, {
      reference_name = self.S:t("ui.workspace.reference_track"),
      yield = function(_, file)
        self.progress = self.S:t("ui.picker.working", { step = tostring(file or ""):match("[^/\\]*$") })
        coroutine.yield()
      end,
    })
    if ws then
      self.result = { ok = true, text = self.S:t("ui.picker.ready"), workspace = ws }
    else
      local d = type(detail) == "string" and detail or ""
      self.result = { ok = false, code = code, text = messages.get(self.S, code, { detail = d, path = d }).text }
    end
  end)
end

function Session:step()
  if not self.job then return true end
  local ok, err = coroutine.resume(self.job)
  if not ok then self.job = nil; self.result = { ok = false, text = tostring(err) }; return true end
  if coroutine.status(self.job) == "dead" then self.job = nil; self:refresh(); return true end
  return false
end

function Session:running() return self.job ~= nil end

-- open(song): open the member's existing workspace
function Session:open(song) if song.workspace then self.env.open(song.workspace) end end

return M
