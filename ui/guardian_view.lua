-- Draws one guardian alert with ReaImGui. The wording asks the person to close the project; the
-- buttons never pretend anything is blocked. Returns "close", "keep", "sync" or "open_right".
local guardian = require("bandcollab.guardian")

local M = {}

local STRONG = 0xE6A700FF
local SOFT = 0x9A9A9AFF

function M.draw(ctx, alert, S)
  local ig = reaper
  local action
  local any_strong, outdated, misplaced = false, nil, nil
  for _, w in ipairs(alert.warnings) do
    if w.severity == "strong" then any_strong = true end
    if w.code == "outdated" then outdated = w end
    if w.code == "misplaced" then misplaced = w end
  end

  ig.ImGui_TextWrapped(ctx, alert.file)
  ig.ImGui_Separator(ctx)
  for _, w in ipairs(alert.warnings) do
    local msg = guardian.text(S, w)
    ig.ImGui_PushStyleColor(ctx, ig.ImGui_Col_Text(), w.severity == "soft" and SOFT or STRONG)
    ig.ImGui_TextWrapped(ctx, msg.what)
    ig.ImGui_PopStyleColor(ctx)
    ig.ImGui_TextWrapped(ctx, msg.action)
    ig.ImGui_Spacing(ctx)
  end

  ig.ImGui_Separator(ctx)
  if any_strong and ig.ImGui_Button(ctx, S:t("guardian.close") .. "##close") then action = "close" end
  if outdated then
    if any_strong then ig.ImGui_SameLine(ctx) end
    if ig.ImGui_Button(ctx, S:t("guardian.open_sync") .. "##sync") then action = "sync" end
  end
  if misplaced then
    if any_strong or outdated then ig.ImGui_SameLine(ctx) end
    if ig.ImGui_Button(ctx, S:t("guardian.open_right") .. "##right") then action = "open_right" end
  end
  if any_strong or outdated or misplaced then ig.ImGui_SameLine(ctx) end
  if ig.ImGui_Button(ctx, S:t("guardian.keep") .. "##keep") then action = "keep" end
  return action
end

return M
