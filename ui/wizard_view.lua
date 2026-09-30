-- Draws the band setup wizard with ReaImGui. Edits the wizard state in place and returns
-- "create" when the user asks to create the band folder and there is nothing left to fix.
local wizard = require("bandcollab.wizard")
local messages = require("bandcollab.messages")

local M = {}

local WARN = 0xE6A700FF
local OK = 0x66B032FF

function M.draw(ctx, state, S, ui)
  local ig = reaper
  local action

  ig.ImGui_Text(ctx, S:t("ui.wizard.band_name"))
  ig.ImGui_SetNextItemWidth(ctx, -1)
  local _, name = ig.ImGui_InputText(ctx, "##band", state.name)
  state.name = name

  ig.ImGui_Text(ctx, S:t("ui.wizard.language"))
  ig.ImGui_SameLine(ctx)
  local fi = ig.ImGui_RadioButton(ctx, "Suomi##fi", state.language == "fi")
  if fi then state.language = "fi" end
  ig.ImGui_SameLine(ctx)
  local en = ig.ImGui_RadioButton(ctx, "English##en", state.language == "en")
  if en then state.language = "en" end
  S.lang = state.language

  ig.ImGui_Text(ctx, S:t("ui.wizard.folder"))
  ig.ImGui_SetNextItemWidth(ctx, -1)
  local _, folder = ig.ImGui_InputText(ctx, "##folder", ui.folder or "")
  ui.folder = folder

  ig.ImGui_Separator(ctx)
  ig.ImGui_Text(ctx, S:t("ui.wizard.members"))

  local remove_member, remove_instrument, add_instrument_to
  for mi, m in ipairs(state.members) do
    ig.ImGui_PushID(ctx, "m" .. mi)
    ig.ImGui_Spacing(ctx)
    ig.ImGui_SetNextItemWidth(ctx, 220)
    local _, mname = ig.ImGui_InputTextWithHint(ctx, "##name", S:t("ui.wizard.member_name"), m.name)
    m.name = mname
    ig.ImGui_SameLine(ctx)
    if ig.ImGui_RadioButton(ctx, S:t("ui.wizard.is_producer") .. "##producer", state.producer == mi) then
      state.producer = mi
    end
    ig.ImGui_SameLine(ctx)
    if ig.ImGui_Button(ctx, S:t("ui.wizard.remove_member") .. "##member") then remove_member = mi end

    for ii, inst in ipairs(m.instruments) do
      ig.ImGui_PushID(ctx, "i" .. ii)
      ig.ImGui_Indent(ctx)
      ig.ImGui_SetNextItemWidth(ctx, 190)
      local _, label = ig.ImGui_InputTextWithHint(ctx, "##label", S:t("ui.wizard.instrument"), inst.label)
      inst.label = label
      ig.ImGui_SameLine(ctx)
      ig.ImGui_Text(ctx, S:t("ui.wizard.tracks"))
      ig.ImGui_SameLine(ctx)
      ig.ImGui_SetNextItemWidth(ctx, 100)
      local _, tracks = ig.ImGui_InputInt(ctx, "##tracks", inst.tracks)
      inst.tracks = tracks
      ig.ImGui_SameLine(ctx)
      if ig.ImGui_Button(ctx, S:t("ui.wizard.remove_instrument") .. "##inst") then remove_instrument = { mi, ii } end
      ig.ImGui_Unindent(ctx)
      ig.ImGui_PopID(ctx)
    end
    ig.ImGui_Indent(ctx)
    if ig.ImGui_Button(ctx, S:t("ui.wizard.add_instrument") .. "##addinst") then add_instrument_to = mi end
    ig.ImGui_Unindent(ctx)
    ig.ImGui_PopID(ctx)
  end

  -- apply structural changes after the loop, so the lists are never edited while being drawn
  if remove_instrument then wizard.remove_instrument(state, remove_instrument[1], remove_instrument[2]) end
  if add_instrument_to then wizard.add_instrument(state, add_instrument_to, "", 1) end
  if remove_member then wizard.remove_member(state, remove_member) end

  ig.ImGui_Spacing(ctx)
  if ig.ImGui_Button(ctx, S:t("ui.wizard.add_member") .. "##addmember") then wizard.add_member(state, "") end

  ig.ImGui_Separator(ctx)
  if ui.show_problems then
    local problems = wizard.problems(state)
    if #problems > 0 then
      ig.ImGui_TextColored(ctx, WARN, S:t("ui.wizard.problems"))
      for _, p in ipairs(problems) do
        local msg = messages.get(S, p.code, { member = p.member, detail = p.detail })
        ig.ImGui_TextWrapped(ctx, "- " .. msg.text)
      end
    end
  end
  if ui.result_error then ig.ImGui_TextColored(ctx, WARN, ui.result_error) end
  if ui.done then ig.ImGui_TextColored(ctx, OK, S:t("ui.wizard.done")) end

  ig.ImGui_Spacing(ctx)
  if ig.ImGui_Button(ctx, S:t("ui.wizard.create") .. "##create") then
    ui.show_problems = true
    if #wizard.problems(state) == 0 then action = "create" end
  end
  return action
end

return M
