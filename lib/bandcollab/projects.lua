-- Creates band template files and song projects in REAPER. Works in its own project tabs and
-- never touches the project the user currently has open.
--
-- One rule holds everywhere: a project tab is only modified after it has been OPENED FROM the
-- file it will be saved to. (Saving an untitled tab, or a tab opened from another file, "as"
-- something else leaves it bound to the old name: Ctrl+S would then overwrite the wrong file --
-- for a song made from the band template, the template itself.)
local pm = require("bandcollab.projectmodel")
local template = require("bandcollab.template")
local slug = require("bandcollab.slug")
local path = require("bandcollab.path")

local M = {}

M.TEMPLATE_PATH = "template/song-template.rpp" -- relative to the band folder

local EMPTY_PROJECT = '<REAPER_PROJECT 0.1 "7.0" 0\n>\n'

local function new_tab()
  reaper.Main_OnCommand(40859, 0) -- File: New project tab
  return (reaper.EnumProjects(-1))
end

local function close_tab(proj)
  reaper.SelectProjectInstance(proj)
  reaper.Main_OnCommand(40860, 0) -- File: Close current project tab
end

-- open_bound(file) -> project tab that was opened from `file`
local function open_bound(file)
  new_tab()
  reaper.Main_openProject("noprompt:" .. file)
  return (reaper.EnumProjects(-1))
end

-- save_bound(proj): saves a project that was opened from its own file (never asks for a name)
local function save_bound(proj)
  reaper.SelectProjectInstance(proj)
  reaper.Main_OnCommand(40026, 0) -- File: Save project
end

local function restore_selection(original)
  if original and reaper.ValidatePtr(original, "ReaProject*") then reaper.SelectProjectInstance(original) end
end

-- create_template(fs, band, counts, file) -> true | nil, err
-- Builds the band's track layout in a project opened from `file`, saves it, and closes the tab.
function M.create_template(fs, band, counts, file)
  local original = (reaper.EnumProjects(-1))
  if not fs.mkdirs(path.dirname(file)) then return nil, "cannot create " .. path.dirname(file) end
  if not fs.write_all(file, EMPTY_PROJECT) then return nil, "cannot write " .. file end
  local proj = open_bound(file)
  pm.apply_plan(proj, template.plan(band, counts))
  pm.set_recording_path(proj)
  pm.set_project_marker(proj, pm.KEY_KIND, "template")
  pm.set_project_marker(proj, pm.KEY_BAND, band.name)
  save_bound(proj)
  close_tab(proj)
  restore_selection(original)
  return true
end

-- create_song(fs, template_file, dest_dir, title [, opts]) -> project file, slug | nil, err
-- The song lives in dest_dir/<slug>/<slug>.rpp, with a slug that is unique in dest_dir. It starts
-- as a copy of the template file and is opened from that copy, so the template is never touched.
--   opts.keep_open = true leaves the new song open in its tab (default: closes it)
function M.create_song(fs, template_file, dest_dir, title, opts)
  opts = opts or {}
  local text = fs.read_all(template_file)
  if not text then return nil, "template not found: " .. template_file end
  local taken = {}
  for _, e in ipairs(fs.list(dest_dir) or {}) do taken[e.name] = true end
  local name = slug.unique(slug.slug(title), taken)
  local dir = dest_dir .. "/" .. name
  if not fs.mkdirs(dir) then return nil, "cannot create " .. dir end
  local file = dir .. "/" .. name .. ".rpp"
  if not fs.write_all(file, text) then return nil, "cannot write " .. file end

  local original = (reaper.EnumProjects(-1))
  local proj = open_bound(file)
  pm.set_project_marker(proj, pm.KEY_KIND, "song")
  reaper.GetSetProjectInfo_String(proj, "PROJECT_TITLE", title, true)
  save_bound(proj)
  if not opts.keep_open then
    close_tab(proj)
    restore_selection(original)
  end
  if not fs.exists(file) then return nil, "song was not saved: " .. file end
  return file, name
end

return M
