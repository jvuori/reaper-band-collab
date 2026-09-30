-- Draws the first-run screen ("Where is the band folder?" and "Who are you?") with ReaImGui.
-- Returns "pick" when the user wants to choose the band file, "confirm" when they are done.
local M = {}

local WARN = 0xE6A700FF
local OK = 0x66B032FF

-- ui = { folder =, choices = { {id,name,roles}... }, selected = id, error = message, done_name = }
function M.draw(ctx, S, ui)
  local ig = reaper
  local action

  ig.ImGui_Text(ctx, S:t("ui.firstrun.step_folder"))
  ig.ImGui_TextWrapped(ctx, S:t("ui.firstrun.pick_hint"))
  if ig.ImGui_Button(ctx, S:t("ui.firstrun.pick_button") .. "##pick") then action = "pick" end

  if ui.error then
    ig.ImGui_Spacing(ctx)
    ig.ImGui_TextColored(ctx, WARN, ui.error.what)
    ig.ImGui_TextWrapped(ctx, ui.error.action)
  end

  if ui.choices then
    ig.ImGui_Spacing(ctx)
    ig.ImGui_TextWrapped(ctx, S:t("ui.firstrun.folder_chosen", { folder = ui.folder }))
    ig.ImGui_Separator(ctx)
    ig.ImGui_Text(ctx, S:t("ui.firstrun.step_member"))
    for _, c in ipairs(ui.choices) do
      local label = c.name .. "  (" .. c.roles .. ")##" .. c.id
      if ig.ImGui_RadioButton(ctx, label, ui.selected == c.id) then ui.selected = c.id end
    end
    ig.ImGui_Spacing(ctx)
    ig.ImGui_BeginDisabled(ctx, ui.selected == nil)
    if ig.ImGui_Button(ctx, S:t("ui.firstrun.confirm") .. "##confirm") then action = "confirm" end
    ig.ImGui_EndDisabled(ctx)
  end

  if ui.done_name then
    ig.ImGui_Spacing(ctx)
    ig.ImGui_TextColored(ctx, OK, S:t("ui.firstrun.ready", { name = ui.done_name }))
  end
  return action
end

return M
