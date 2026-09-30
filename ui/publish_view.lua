-- Draws the "publish a version" panel with ReaImGui. Edits the session's note and requests in
-- place and returns "publish" when the producer asks to publish.
local M = {}

local WARN = 0xE6A700FF
local OK = 0x66B032FF
local DIM = 0x9A9A9AFF

function M.draw(ctx, sess, S)
  local ig = reaper
  local action
  local status = sess.status

  if status.kind == "no_song" or status.kind == "unsaved" then
    local code = status.kind == "unsaved" and "project_unsaved" or "not_a_song"
    ig.ImGui_TextColored(ctx, WARN, S:t("err." .. code .. ".what"))
    ig.ImGui_TextWrapped(ctx, S:t("err." .. code .. ".action"))
  elseif status.kind == "ready" then
    ig.ImGui_Text(ctx, S:t("ui.publish.song", { title = status.song.title }))
    ig.ImGui_TextColored(ctx, DIM, status.last and S:t("ui.publish.last", { n = status.last }) or S:t("ui.publish.first"))
    ig.ImGui_Text(ctx, S:t("ui.publish.next", { n = status.next }))
  end

  if status.kind == "ready" then
    ig.ImGui_Separator(ctx)
    ig.ImGui_Text(ctx, S:t("ui.publish.note_summary"))
    ig.ImGui_SetNextItemWidth(ctx, -1)
    local _, summary = ig.ImGui_InputText(ctx, "##summary", sess.note.summary)
    sess.note.summary = summary
    ig.ImGui_Text(ctx, S:t("ui.publish.note_body"))
    local _, body = ig.ImGui_InputTextMultiline(ctx, "##body", sess.note.body, -1, 70)
    sess.note.body = body

    ig.ImGui_Separator(ctx)
    ig.ImGui_Text(ctx, S:t("ui.publish.tasks"))
    local remove
    for i, task in ipairs(sess.tasks) do
      ig.ImGui_PushID(ctx, "task" .. i)
      ig.ImGui_SetNextItemWidth(ctx, 150)
      local _, who = ig.ImGui_InputTextWithHint(ctx, "##who", S:t("ui.publish.task_who"), task.who)
      task.who = who
      ig.ImGui_SameLine(ctx)
      ig.ImGui_SetNextItemWidth(ctx, 300)
      local _, text = ig.ImGui_InputTextWithHint(ctx, "##text", S:t("ui.publish.task_text"), task.text)
      task.text = text
      ig.ImGui_SameLine(ctx)
      if ig.ImGui_Button(ctx, S:t("ui.publish.remove_task") .. "##remove") then remove = i end
      ig.ImGui_PopID(ctx)
    end
    if remove then sess:remove_task(remove) end
    if ig.ImGui_Button(ctx, S:t("ui.publish.add_task") .. "##addtask") then sess:add_task("", "") end

    ig.ImGui_Separator(ctx)
    ig.ImGui_BeginDisabled(ctx, sess:running())
    if ig.ImGui_Button(ctx, S:t("ui.publish.button") .. "##publish") then action = "publish" end
    ig.ImGui_EndDisabled(ctx)
    if sess:running() then ig.ImGui_Text(ctx, S:t("ui.publish.publishing", { step = sess.progress })) end
  end

  if sess.result then
    ig.ImGui_Spacing(ctx)
    ig.ImGui_TextColored(ctx, sess.result.ok and OK or WARN, sess.result.text)
    if sess.result.ok and sess.result.structure and sess.result.structure.changed then
      ig.ImGui_TextWrapped(ctx, S:t("ui.publish.structure_warning"))
    end
  end
  return action
end

return M
