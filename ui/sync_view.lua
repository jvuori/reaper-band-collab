-- Draws the "Synkronoi" panel with ReaImGui. It offers only the directions that make sense, never
-- picks one for the member, and shows the second step as waiting while the first is still to do.
-- Returns "fetch", "send" or "undo" when the member asks for one.
local M = {}

local WARN = 0xE6A700FF
local OK = 0x66B032FF
local DIM = 0x9A9A9AFF

function M.draw(ctx, sess)
  local ig, S = reaper, sess.S
  local action
  local st = sess.status
  local cards = sess:cards()

  ig.ImGui_Text(ctx, S:t("ui.sync.song", { title = sess.ws.state.song.title, member = sess.ws.state.member }))
  ig.ImGui_TextColored(ctx, DIM, S:t("ui.sync.based_on", { n = st.base }))
  ig.ImGui_Separator(ctx)

  if cards.arriving then ig.ImGui_TextColored(ctx, WARN, S:t("ui.sync.arriving")) end
  if cards.nothing then ig.ImGui_TextColored(ctx, OK, S:t("ui.sync.all_current")) end
  if cards.closed then ig.ImGui_TextColored(ctx, WARN, S:t("ui.sync.closed")) end

  if cards.fetch then
    ig.ImGui_Text(ctx, S:t("ui.sync.step1"))
    ig.ImGui_TextWrapped(ctx, S:t("ui.sync.step1_hint"))
    ig.ImGui_BeginDisabled(ctx, sess:running())
    if ig.ImGui_Button(ctx, S:t("ui.sync.step1_button") .. "##fetch") then action = "fetch" end
    ig.ImGui_EndDisabled(ctx)
    ig.ImGui_Spacing(ctx)
    ig.ImGui_Separator(ctx)
  end

  if cards.propose then
    ig.ImGui_Text(ctx, S:t("ui.sync.step2"))
    ig.ImGui_TextWrapped(ctx, S:t("ui.sync.step2_hint"))
    if cards.propose_waits then ig.ImGui_TextColored(ctx, DIM, S:t("ui.sync.step2_wait")) end
    ig.ImGui_BeginDisabled(ctx, cards.propose_waits or sess:running())
    ig.ImGui_Text(ctx, S:t("ui.sync.note_summary"))
    ig.ImGui_SetNextItemWidth(ctx, -1)
    local _, summary = ig.ImGui_InputText(ctx, "##summary", sess.note.summary)
    sess.note.summary = summary
    ig.ImGui_Text(ctx, S:t("ui.sync.note_body"))
    local _, body = ig.ImGui_InputTextMultiline(ctx, "##body", sess.note.body, -1, 60)
    sess.note.body = body

    -- what the check found: things to fix (with a button where the tool can do it) and things to confirm
    local list = sess:problems()
    if #list > 0 then
      ig.ImGui_Spacing(ctx)
      ig.ImGui_TextColored(ctx, WARN, S:t("ui.sync.before_sending"))
      for i, problem in ipairs(list) do
        ig.ImGui_PushID(ctx, "problem" .. i)
        ig.ImGui_TextWrapped(ctx, "- " .. problem.text)
        if problem.fix then
          ig.ImGui_Indent(ctx)
          if ig.ImGui_Button(ctx, S:t("ui.sync.fix_orphans") .. "##fix") then sess:apply_fix(problem) end
          ig.ImGui_Unindent(ctx)
        elseif problem.severity == "warning" then
          ig.ImGui_Indent(ctx)
          local _, yes = ig.ImGui_Checkbox(ctx, S:t("ui.sync.confirm") .. "##confirm", problem.confirmed)
          sess:acknowledge(problem.code, yes)
          ig.ImGui_Unindent(ctx)
        end
        ig.ImGui_PopID(ctx)
      end
    end
    ig.ImGui_Spacing(ctx)
    if ig.ImGui_Button(ctx, S:t("ui.sync.step2_button") .. "##send") then action = "send" end
    ig.ImGui_EndDisabled(ctx)
    ig.ImGui_Spacing(ctx)
    ig.ImGui_Separator(ctx)
  end

  if sess:running() and sess.progress ~= "" then ig.ImGui_Text(ctx, sess.progress) end
  if sess.result then
    ig.ImGui_TextColored(ctx, sess.result.ok and OK or WARN, sess.result.text)
    if sess.result.warning then ig.ImGui_TextWrapped(ctx, sess.result.warning) end
  end
  local line = sess:proposal_text()
  if line then ig.ImGui_TextColored(ctx, DIM, line) end

  if sess.undo_from then
    ig.ImGui_Spacing(ctx)
    ig.ImGui_Separator(ctx)
    ig.ImGui_TextWrapped(ctx, S:t("ui.sync.undo_hint", { n = sess.undo_from }))
    ig.ImGui_BeginDisabled(ctx, sess:running())
    if ig.ImGui_Button(ctx, S:t("ui.sync.undo_button") .. "##undo") then action = "undo" end
    ig.ImGui_EndDisabled(ctx)
  end
  return action
end

return M
