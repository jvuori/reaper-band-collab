-- @description Band setup wizard (producer): creates the band folder settings and the band template
-- @version 0.0.1
local dir = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
local boot = dofile(dir .. "/bootstrap.lua")(dir)

if not reaper.APIExists("ImGui_CreateContext") then
  reaper.ShowMessageBox("ReaImGui is not installed. Install it with ReaPack (ReaTeam Extensions).", "Band Collab", 0)
  return
end

local wizard = require("bandcollab.wizard")
local projects = require("bandcollab.projects")
local messages = require("bandcollab.messages")
local fs = require("bandcollab.fs_std")
local view = require("wizard_view")

local S = boot.strings("fi")
local state = wizard.new("fi")
wizard.add_member(state, "")
local ui = { folder = "" }

local ctx = reaper.ImGui_CreateContext("bandcollab_setup")

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 620, 640, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, S:t("ui.wizard.title"), true)
  if visible then
    if view.draw(ctx, state, S, ui) == "create" then
      local band, problems = wizard.create(fs, projects, ui.folder, state, S)
      if band then
        ui.done, ui.result_error = true, nil
      else
        ui.done = false
        local p = problems[1]
        ui.result_error = messages.get(S, p.code, { detail = p.detail }).text
      end
    end
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end
reaper.defer(loop)
