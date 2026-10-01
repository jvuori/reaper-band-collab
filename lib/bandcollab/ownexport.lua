-- Exports a role folder of the open project as files: its tracks (a chunk file) and the media they
-- use, under safe unique names, with the chunk's FILE lines pointing at them. Used for the folders
-- of a publication and for the folders of a member's delivery. Needs the REAPER API.
local copytree = require("bandcollab.copytree")
local inspect = require("bandcollab.inspect")
local slug = require("bandcollab.slug")
local rpp = require("bandcollab.rpp")
local path = require("bandcollab.path")

local M = {}

-- export(fs, proj, folder, dir, project_dir [, yield]) -> number of media files | nil, err
--   folder: a role folder from projectmodel.role_folders; dir: where tracks.chunk and media/ are written;
--   project_dir: the folder of the project, against which relative media paths are resolved.
--   Media outside the project folder is copied in as well (nothing is left pointing elsewhere).
function M.export(fs, proj, folder, dir, project_dir, yield)
  if not fs.mkdirs(dir) then return nil, "cannot create " .. dir end -- also for a folder that holds no media
  local chunks = {}
  for i = folder.index, folder.last do
    local _, chunk = reaper.GetTrackStateChunk(reaper.GetTrack(proj, i - 1), "", false)
    chunks[#chunks + 1] = chunk
  end
  local text = table.concat(chunks, "\n")
  local map, used, count = {}, {}, 0
  for _, ref in ipairs(rpp.media_refs(text)) do
    local source = inspect.resolve(project_dir, ref)
    local base, ext = path.basename(source):match("^(.*)(%.[^.]*)$")
    if not base then base, ext = path.basename(source), "" end
    local name = slug.unique(slug.slug(base), used) .. ext:lower()
    used[name:gsub("%.[^.]*$", "")] = true
    used[slug.slug(base)] = true
    if not fs.mkdirs(dir .. "/media") then return nil, "cannot create " .. dir .. "/media" end
    local ok, err = copytree.copy_file(fs, source, dir .. "/media/" .. name, yield)
    if not ok then return nil, "cannot copy " .. ref .. ": " .. tostring(err) end
    map[ref] = "media/" .. name
    count = count + 1
  end
  local written, werr = fs.write_all(dir .. "/tracks.chunk", rpp.rewrite_media(text, map))
  if not written then return nil, werr end
  return count
end

return M
