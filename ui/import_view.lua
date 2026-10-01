-- Draws the producer's "Ehdotukset" panel with ReaImGui. Returns ("review", entry), "accept",
-- "cancel" or "undo" when the producer asks for one of those. Nothing happens without a click.
local M = {}

local WARN = 0xE6A700FF
local OK = 0x66B032FF
local DIM = 0x9A9A9AFF

function M.draw(ctx, sess)
  local ig, S = reaper, sess.S
  local action, target

  if #sess.inbox.pending == 0 then ig.ImGui_TextColored(ctx, DIM, S:t("ui.import.empty")) end
  for i, entry in ipairs(sess.inbox.pending) do
    ig.ImGui_PushID(ctx, "entry" .. i)
    local selected = sess.selected and sess.selected.delivery == entry.delivery
    ig.ImGui_Text(ctx, (selected and "> " or "") .. sess:row_text(entry))
    local tag = sess:tag(entry)
    if tag then ig.ImGui_SameLine(ctx); ig.ImGui_TextColored(ctx, WARN, tag) end
    if entry.note and entry.note.summary and entry.note.summary ~= "" then
      ig.ImGui_Indent(ctx); ig.ImGui_TextColored(ctx, DIM, entry.note.summary); ig.ImGui_Unindent(ctx)
    end
    ig.ImGui_Indent(ctx)
    ig.ImGui_BeginDisabled(ctx, sess:running())
    if ig.ImGui_Button(ctx, S:t("ui.import.review") .. "##review") then action, target = "review", entry end
    ig.ImGui_EndDisabled(ctx)
    ig.ImGui_Unindent(ctx)
    ig.ImGui_PopID(ctx)
  end
  for _, a in ipairs(sess.inbox.arriving) do
    ig.ImGui_TextColored(ctx, DIM, S:t("ui.import.arriving", { member = a.member_name }))
  end

  if sess.problem then
    ig.ImGui_Separator(ctx)
    ig.ImGui_TextColored(ctx, WARN, sess.problem.text)
  end

  if sess.preview then
    ig.ImGui_Separator(ctx)
    ig.ImGui_Text(ctx, S:t("ui.import.preview_title"))
    for _, line in ipairs(sess:lines()) do ig.ImGui_TextWrapped(ctx, "- " .. line) end
    for _, w in ipairs(sess:warnings()) do
      ig.ImGui_PushStyleColor(ctx, ig.ImGui_Col_Text(), w.severity == "warning" and WARN or DIM)
      ig.ImGui_TextWrapped(ctx, "! " .. w.text)
      ig.ImGui_PopStyleColor(ctx)
    end
    ig.ImGui_Spacing(ctx)
    ig.ImGui_Text(ctx, S:t("ui.import.note_summary"))
    ig.ImGui_SetNextItemWidth(ctx, -1)
    local _, summary = ig.ImGui_InputText(ctx, "##summary", sess.note.summary)
    sess.note.summary = summary
    ig.ImGui_Text(ctx, S:t("ui.import.note_body"))
    local _, body = ig.ImGui_InputTextMultiline(ctx, "##body", sess.note.body, -1, 56)
    sess.note.body = body
    ig.ImGui_Spacing(ctx)
    ig.ImGui_BeginDisabled(ctx, sess:running())
    if ig.ImGui_Button(ctx, S:t("ui.import.accept") .. "##accept") then action = "accept" end
    ig.ImGui_SameLine(ctx)
    if ig.ImGui_Button(ctx, S:t("ui.import.cancel") .. "##cancel") then action = "cancel" end
    ig.ImGui_EndDisabled(ctx)
  end

  if sess:running() and sess.progress ~= "" then ig.ImGui_Text(ctx, sess.progress) end
  if sess.result then ig.ImGui_TextColored(ctx, sess.result.ok and OK or WARN, sess.result.text) end

  if sess.undo_delivery then
    ig.ImGui_Separator(ctx)
    ig.ImGui_TextWrapped(ctx, S:t("ui.import.undo_hint", { delivery = sess.undo_delivery }))
    ig.ImGui_BeginDisabled(ctx, sess:running())
    if ig.ImGui_Button(ctx, S:t("ui.import.undo_button") .. "##undo") then action = "undo" end
    ig.ImGui_EndDisabled(ctx)
  end
  return action, target
end

return M
