-- Draws the "Tarkista kansiot" panel with ReaImGui. Reports; changes nothing on its own.
-- Returns "run" (check again) or ("delete", problem) when the producer asks to delete one leftover.
local foldercheck = require("bandcollab.foldercheck")

local M = {}

local WARN = 0xE6A700FF
local OK = 0x66B032FF
local DIM = 0x9A9A9AFF

-- state = { ran = bool, problems = {...}, tidy = {...} }
function M.draw(ctx, state, S)
  local ig = reaper
  local action, target
  if ig.ImGui_Button(ctx, S:t("check.run") .. "##run") then action = "run" end

  if state.ran then
    ig.ImGui_Spacing(ctx)
    if #state.problems == 0 then
      ig.ImGui_TextColored(ctx, OK, S:t("check.clean"))
    else
      ig.ImGui_TextColored(ctx, WARN, S:t("check.problems_header"))
      ig.ImGui_TextColored(ctx, DIM, S:t("check.found", { n = #state.problems }))
      for i, p in ipairs(state.problems) do
        local d = foldercheck.describe(S, p)
        ig.ImGui_PushID(ctx, "p" .. i)
        ig.ImGui_TextWrapped(ctx, "- " .. d.what)
        ig.ImGui_Indent(ctx); ig.ImGui_TextColored(ctx, DIM, d.action); ig.ImGui_Unindent(ctx)
        ig.ImGui_PopID(ctx)
      end
    end
    if #state.tidy > 0 then
      ig.ImGui_Separator(ctx)
      ig.ImGui_TextColored(ctx, DIM, S:t("check.tidy", { n = #state.tidy }))
      for i, p in ipairs(state.tidy) do
        ig.ImGui_PushID(ctx, "t" .. i)
        ig.ImGui_TextWrapped(ctx, p.path)
        ig.ImGui_SameLine(ctx)
        if ig.ImGui_Button(ctx, S:t("check.delete") .. "##delete") then action, target = "delete", p end
        ig.ImGui_PopID(ctx)
      end
    end
  end
  return action, target
end

return M
