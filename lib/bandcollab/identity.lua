-- Decides what an arriving project is: a new song, a song that has moved, a copy of a song
-- that still exists elsewhere, or something already received.
local songfile = require("bandcollab.songfile")
local path = require("bandcollab.path")
local registry = require("bandcollab.registry")

local M = {}

-- classify(fs, band_folder, reg, project_dir [, source_hash]) -> { state =, id =, entry = }
--   "new"               no identity yet, or an unregistered one: register it (keeping the id if it has one)
--   "same"              the project is already inside the band folder at its registered place
--   "moved"             registered elsewhere, but that place no longer exists: update silently
--   "copy"              registered elsewhere and that place still exists: the producer must decide
--   "already_received"  a project with exactly this content was received before
function M.classify(fs, band_folder, reg, project_dir, source_hash)
  local song = songfile.read(fs, project_dir)
  if not song then
    local dup = source_hash and registry.find_by_source_hash(reg, source_hash)
    if dup then return { state = "already_received", id = dup.id, entry = dup } end
    return { state = "new" }
  end
  local entry = registry.get(reg, song.id)
  if not entry then return { state = "new", id = song.id } end

  local registered_dir = band_folder .. "/" .. entry.path
  if path.same(project_dir, registered_dir) then return { state = "same", id = song.id, entry = entry } end
  if fs.exists(registered_dir .. "/" .. songfile.FILENAME) then return { state = "copy", id = song.id, entry = entry } end
  return { state = "moved", id = song.id, entry = entry }
end

return M
