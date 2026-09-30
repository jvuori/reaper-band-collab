-- Creates band template files and song projects in REAPER. Works in its own project tab and
-- never touches the project the user currently has open.
local pm = require("bandcollab.projectmodel")
local template = require("bandcollab.template")
local slug = require("bandcollab.slug")
local path = require("bandcollab.path")

local M = {}

M.TEMPLATE_PATH = "template/song-template.rpp" -- relative to the band folder

local function new_tab()
  reaper.Main_OnCommand(40859, 0) -- File: New project tab
  return (reaper.EnumProjects(-1))
end

local function close_tab(proj)
  reaper.SelectProjectInstance(proj)
  reaper.Main_OnCommand(40860, 0) -- File: Close current project tab
end

-- create_template(fs, band, counts, file) -> true | nil, err
-- Builds the band's track layout in a new tab, saves it as `file`, and closes the tab again.
function M.create_template(fs, band, counts, file)
  local original = (reaper.EnumProjects(-1))
  local ok = fs.mkdirs(path.dirname(file))
  if not ok then return nil, "cannot create " .. path.dirname(file) end
  local proj = new_tab()
  pm.apply_plan(proj, template.plan(band, counts))
  pm.set_recording_path(proj)
  pm.set_project_marker(proj, pm.KEY_KIND, "template")
  pm.set_project_marker(proj, pm.KEY_BAND, band.name)
  reaper.Main_SaveProjectEx(proj, file, 0)
  close_tab(proj)
  if reaper.ValidatePtr(original, "ReaProject*") then reaper.SelectProjectInstance(original) end
  if not fs.exists(file) then return nil, "template was not saved: " .. file end
  return true
end

-- create_song(fs, template_file, dest_dir, title [, opts]) -> project file | nil, err
-- The song lives in dest_dir/<slug>/<slug>.rpp, with a slug that is unique in dest_dir.
--   opts.keep_open = true leaves the new song open in its tab (default: closes it)
function M.create_song(fs, template_file, dest_dir, title, opts)
  opts = opts or {}
  if not fs.exists(template_file) then return nil, "template not found: " .. template_file end
  local taken = {}
  for _, e in ipairs(fs.list(dest_dir) or {}) do taken[e.name] = true end
  local name = slug.unique(slug.slug(title), taken)
  local dir = dest_dir .. "/" .. name
  if not fs.mkdirs(dir) then return nil, "cannot create " .. dir end
  local file = dir .. "/" .. name .. ".rpp"

  local original = (reaper.EnumProjects(-1))
  local proj = new_tab()
  reaper.Main_openProject("noprompt:" .. template_file)
  proj = (reaper.EnumProjects(-1))
  reaper.Main_SaveProjectEx(proj, file, 0) -- saving under the new name leaves the template untouched
  pm.set_project_marker(proj, pm.KEY_KIND, "song")
  reaper.GetSetProjectInfo_String(proj, "PROJECT_TITLE", title, true)
  reaper.Main_SaveProjectEx(proj, file, 0)
  if not opts.keep_open then
    close_tab(proj)
    if reaper.ValidatePtr(original, "ReaProject*") then reaper.SelectProjectInstance(original) end
  end
  if not fs.exists(file) then return nil, "song was not saved: " .. file end
  return file, name
end

return M
