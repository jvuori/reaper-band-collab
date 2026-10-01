-- The guardian: decides whether the project someone has just opened is the wrong one for them, and
-- says so in plain words. It speaks ONLY about managed projects (a registered song's master, or a
-- member's workspace); an ordinary project never gets a message. It can warn and offer to close the
-- project; it cannot stop anyone from editing or saving, and its words never claim otherwise.
-- This module is pure logic over files; watching REAPER lives in guardian_watch.lua.
local songfile = require("bandcollab.songfile")
local wm = require("bandcollab.workspace_model")
local songs_list = require("bandcollab.songs_list")
local cycles = require("bandcollab.cycles")
local bandfile = require("bandcollab.bandfile")
local messages = require("bandcollab.messages")
local json = require("bandcollab.json")
local path = require("bandcollab.path")

local M = {}

-- inspect(fs, facts) -> { role = "master" | "workspace" | "workspace_orphan" | "managed", ... } | nil
--   facts = { file = path of the project, marker_kind = "song" | "workspace" | "template" | nil }
--   marker_kind is the hidden marker the tool writes into the project itself.
function M.inspect(fs, facts)
  if not facts.file or facts.file == "" then return nil end
  local dir = path.dirname(facts.file)
  local song = songfile.read(fs, dir)
  if song then return { role = "master", song = song, dir = dir } end
  local state = wm.read_state(fs, path.dirname(dir))
  if state and path.basename(dir) == "work" then return { role = "workspace", state = state, dir = path.dirname(dir) } end
  if facts.marker_kind == "workspace" then return { role = "workspace_orphan" } end
  if facts.marker_kind == "song" or facts.marker_kind == "template" then return { role = "managed" } end
  return nil
end

local function member_name(band, id)
  for _, m in ipairs(band.members) do if m.id == id then return m.name end end
  return nil
end

-- check(fs, band, band_folder, member, facts) -> { info =, warnings = { {code =, severity =, vars =} } }
--   member: the id chosen on this machine (nil when not set up yet)
--   severity: "strong" (offers to close the project), "warning", "soft" (a gentle, non-blocking notice)
-- An unmanaged project gives { info = nil, warnings = {} }.
function M.check(fs, band, band_folder, member, facts)
  local info = M.inspect(fs, facts)
  local out = { info = info, warnings = {} }
  if not info then return out end
  local function add(code, severity, vars) out.warnings[#out.warnings + 1] = { code = code, severity = severity, vars = vars } end

  if info.role == "master" then
    if member ~= band.producer then add("master", "strong") end
  elseif info.role == "workspace" then
    local state = info.state
    if member and state.member ~= member then
      local owner = member_name(band, state.member)
      if owner then add("other_workspace", "strong", { owner = owner, you = member_name(band, member) or member })
      else add("unknown_owner", "strong") end
    else
      local expected = wm.project_file(wm.dir(band, band_folder, state.member, state.song), state.song.slug)
      if not path.same(facts.file, expected) then add("misplaced", "warning", { where = expected }) end
      if not cycles.check_open(fs, band, band_folder, state.song.library, state.song.cycle) then add("closed_cycle", "warning") end
      local lib = bandfile.library(band, state.song.library)
      local pub = cycles.dir(band, band_folder, "publications", state.song.library, lib and lib.kind == "dated" and state.song.cycle or nil) .. "/" .. state.song.slug
      local latest = songs_list.latest_usable(fs, pub)
      if latest and latest.number > state.base_revision then add("outdated", "soft", { latest = latest.number, base = state.base_revision }) end
    end
  elseif info.role == "workspace_orphan" then
    add("misplaced_unknown", "warning")
  end
  return out
end

-- text(S, warning) -> { what =, action =, text = } for a warning from check()
function M.text(S, warning)
  local what = S:t("guardian." .. warning.code .. ".what", warning.vars)
  local action = S:t("guardian." .. warning.code .. ".action", warning.vars)
  return { code = warning.code, what = what, action = action, text = what .. " " .. action }
end

-- Tracker: each warning is shown once per open of a project, not again while the person keeps
-- working. An "open" is a project tab together with the file it holds, so opening another file in
-- the same tab, or reopening a project, starts afresh.
local Tracker = {}
Tracker.__index = Tracker

function M.new_tracker() return setmetatable({ shown = {}, seen = {} }, Tracker) end

local function key(handle, file) return tostring(handle) .. "|" .. tostring(file) end

-- is_new_open(handle, file) -> true the first time this tab/file pair is seen
function Tracker:is_new_open(handle, file)
  local k = key(handle, file)
  if self.seen[k] then return false end
  self.seen[k] = true
  return true
end

-- should_show(handle, file, code) -> true once per code per open
function Tracker:should_show(handle, file, code)
  local k = key(handle, file) .. "|" .. code
  if self.shown[k] then return false end
  self.shown[k] = true
  return true
end

-- forget_closed(live): live is a set of "handle|file" keys currently open; everything else is dropped
function Tracker:forget_closed(live)
  for k in pairs(self.seen) do if not live[k] then self.seen[k] = nil end end
  for k in pairs(self.shown) do
    local base = k:match("^(.*)|[^|]*$")
    if not live[base] then self.shown[k] = nil end
  end
end

M.key = key

-- log_event(fs, band, band_folder, member, code, file, now) -> true | nil, err
-- Appends one line to the member's own guardian.log (in their own proposals folder, so only they
-- write it and the producer can read it).
function M.log_event(fs, band, band_folder, member, code, file, now)
  local dir = band_folder .. "/" .. band.locations.proposals .. "/" .. (member or "unknown")
  if not fs.mkdirs(dir) then return nil, "cannot create " .. dir end
  local logfile = dir .. "/guardian.log"
  local line = json.encode({ at = now, code = code, file = file })
  return fs.write_all(logfile, (fs.read_all(logfile) or "") .. line .. "\n")
end

return M
