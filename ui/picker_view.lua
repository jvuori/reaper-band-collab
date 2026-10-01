-- Draws the "Oma työtila" panel with ReaImGui. Returns { "create", song } or { "open", song }
-- when the member picks one of the buttons.
local M = {}

local WARN = 0xE6A700FF
local OK = 0x66B032FF
local DIM = 0x9A9A9AFF

function M.draw(ctx, sess)
  local ig, S = reaper, sess.S
  local action, target

  ig.ImGui_TextWrapped(ctx, S:t("ui.picker.intro"))
  ig.ImGui_TextColored(ctx, DIM, sess:who())
  ig.ImGui_Separator(ctx)

  local empty = sess:empty_message()
  if empty then ig.ImGui_TextColored(ctx, WARN, empty) end

  for i, song in ipairs(sess.songs) do
    ig.ImGui_PushID(ctx, "song" .. i)
    local where = song.library_label .. (song.cycle and (", " .. song.cycle) or "")
    ig.ImGui_Text(ctx, song.title)
    ig.ImGui_SameLine(ctx)
    ig.ImGui_TextColored(ctx, DIM, "(" .. where .. ")")
    if song.closed then
      ig.ImGui_SameLine(ctx)
      ig.ImGui_TextColored(ctx, WARN, S:t("ui.picker.closed"))
    end
    ig.ImGui_Indent(ctx)
    if song.workspace then
      if ig.ImGui_Button(ctx, S:t("ui.picker.open") .. "##open") then action, target = "open", song end
    else
      ig.ImGui_BeginDisabled(ctx, not sess:can_create(song) or sess:running())
      if ig.ImGui_Button(ctx, S:t("ui.picker.create") .. "##create") then action, target = "create", song end
      ig.ImGui_EndDisabled(ctx)
    end
    ig.ImGui_Unindent(ctx)
    ig.ImGui_Spacing(ctx)
    ig.ImGui_PopID(ctx)
  end

  for _, song in ipairs(sess.arriving) do
    ig.ImGui_TextColored(ctx, DIM, S:t("ui.picker.arriving_song", { title = song.title }))
  end
  if sess:running() and sess.progress ~= "" then ig.ImGui_Text(ctx, sess.progress) end
  if sess.result then ig.ImGui_TextColored(ctx, sess.result.ok and OK or WARN, sess.result.text) end
  return action, target
end

return M
