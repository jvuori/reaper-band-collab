-- @description First-run setup (members): choose the band folder and say who you are
-- @version 0.0.1
local dir = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
local boot = dofile(dir .. "/bootstrap.lua")(dir)

if not reaper.APIExists("ImGui_CreateContext") then
  reaper.ShowMessageBox("ReaImGui is not installed. Install it with ReaPack (ReaTeam Extensions).", "Band Collab", 0)
  return
end

local firstrun = require("bandcollab.firstrun")
local localsettings = require("bandcollab.localsettings")
local messages = require("bandcollab.messages")
local fs = require("bandcollab.fs_std")
local path = require("bandcollab.path")
local view = require("firstrun_view")

local S = boot.strings("fi")
local settings = localsettings.new(localsettings.reaper_backend())
local ui = {}
local band

local ctx = reaper.ImGui_CreateContext("bandcollab_first_run")

local function pick()
  local ok, file = reaper.GetUserFileNameForRead("", S:t("ui.firstrun.pick_title"), "json")
  if not ok then return end
  local folder = firstrun.folder_from_file(file)
  local found, code, detail = firstrun.check_folder(fs, folder)
  if not found then
    ui.choices, ui.selected, ui.folder = nil, nil, nil
    ui.error = messages.get(S, code, { detail = detail })
    return
  end
  band, ui.error, ui.folder = found, nil, folder
  S.lang = found.language
  ui.choices = firstrun.member_choices(found)
  ui.selected = nil
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 520, 360, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, S:t("ui.firstrun.title"), true)
  if visible then
    local action = view.draw(ctx, S, ui)
    if action == "pick" then pick()
    elseif action == "confirm" then
      local ok, code = firstrun.complete(settings, band, ui.folder, ui.selected)
      if ok then
        for _, c in ipairs(ui.choices) do if c.id == ui.selected then ui.done_name = c.name end end
      else
        ui.error = messages.get(S, code)
      end
    end
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end
reaper.defer(loop)
