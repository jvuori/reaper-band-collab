-- Draws the "receive a rehearsal" panel with ReaImGui. Edits the session in place and returns
-- "pick", "scan" or "start" when the user asks for one of those actions.
local M = {}

local WARN = 0xE6A700FF
local OK = 0x66B032FF
local DIM = 0x9A9A9AFF

local KIND_COLOR = { ok = OK, problem = WARN, copy = WARN, already = DIM }

-- ui = { staging = "", scanned = bool }
function M.draw(ctx, sess, ui)
  local ig, S = reaper, sess.S
  local action

  ig.ImGui_Text(ctx, S:t("ui.receive.staging"))
  ig.ImGui_SetNextItemWidth(ctx, -1)
  local _, staging = ig.ImGui_InputText(ctx, "##staging", ui.staging or "")
  ui.staging = staging
  if ig.ImGui_Button(ctx, S:t("ui.receive.pick_button") .. "##pick") then action = "pick" end
  ig.ImGui_SameLine(ctx)
  if ig.ImGui_Button(ctx, S:t("ui.receive.scan") .. "##scan") then action = "scan" end

  if ui.scanned and #sess.rows == 0 then
    ig.ImGui_Spacing(ctx)
    ig.ImGui_TextColored(ctx, WARN, S:t("ui.receive.no_songs"))
  end

  if #sess.rows > 0 then
    ig.ImGui_Separator(ctx)
    ig.ImGui_Text(ctx, S:t("ui.receive.library"))
    for _, lib in ipairs(sess:libraries()) do
      ig.ImGui_SameLine(ctx)
      if ig.ImGui_RadioButton(ctx, lib.label .. "##lib" .. lib.id, sess.library == lib.id) then sess.library = lib.id end
    end
    local dated = false
    for _, lib in ipairs(sess:libraries()) do if lib.id == sess.library and lib.kind == "dated" then dated = true end end
    if dated then
      ig.ImGui_Text(ctx, S:t("ui.receive.cycle"))
      ig.ImGui_SetNextItemWidth(ctx, 140)
      local _, cycle = ig.ImGui_InputText(ctx, "##cycle", sess.cycle)
      sess.cycle = cycle
    end

    ig.ImGui_Separator(ctx)
    for i, row in ipairs(sess.rows) do
      ig.ImGui_PushID(ctx, "row" .. i)
      ig.ImGui_BeginDisabled(ctx, not sess:can_select(row) or sess:running())
      local _, sel = ig.ImGui_Checkbox(ctx, "##sel", row.selected)
      row.selected = sel and sess:can_select(row)
      ig.ImGui_EndDisabled(ctx)
      ig.ImGui_SameLine(ctx)
      ig.ImGui_SetNextItemWidth(ctx, 240)
      local _, title = ig.ImGui_InputText(ctx, "##title", row.title)
      row.title = title
      ig.ImGui_SameLine(ctx)
      ig.ImGui_TextColored(ctx, KIND_COLOR[row.status.kind] or DIM, row.status.text)
      if row.status.kind == "copy" then
        ig.ImGui_Indent(ctx)
        if ig.ImGui_Button(ctx, S:t("ui.receive.song_is_copy") .. "##copy") then sess:decide(row, "copy") end
        ig.ImGui_SameLine(ctx)
        if ig.ImGui_Button(ctx, S:t("ui.receive.song_skip") .. "##skip") then sess:decide(row, "skip") end
        ig.ImGui_Unindent(ctx)
      end
      ig.ImGui_PopID(ctx)
    end

    ig.ImGui_Spacing(ctx)
    ig.ImGui_BeginDisabled(ctx, sess:running() or #sess:ready_rows() == 0)
    if ig.ImGui_Button(ctx, S:t("ui.receive.receive_button") .. "##start") then action = "start" end
    ig.ImGui_EndDisabled(ctx)
    if sess:running() and sess.progress ~= "" then ig.ImGui_Text(ctx, sess.progress) end
  end

  for _, r in ipairs(sess.results) do
    ig.ImGui_TextColored(ctx, r.ok and OK or WARN, r.text)
  end

  local any_cycles = false
  for _, lib in ipairs(sess:libraries()) do
    if lib.kind == "dated" and #sess:cycles_of(lib.id) > 0 then any_cycles = true end
  end
  if any_cycles then
    ig.ImGui_Separator(ctx)
    ig.ImGui_Text(ctx, S:t("ui.receive.cycles"))
    for _, lib in ipairs(sess:libraries()) do
      for _, c in ipairs(sess:cycles_of(lib.id)) do
        ig.ImGui_PushID(ctx, lib.id .. c.cycle)
        local closed = c.state == "closed"
        ig.ImGui_Text(ctx, lib.label .. "  " .. c.cycle .. "  ")
        ig.ImGui_SameLine(ctx)
        ig.ImGui_TextColored(ctx, closed and DIM or OK, S:t(closed and "ui.receive.cycle_closed" or "ui.receive.cycle_open"))
        if not closed then
          ig.ImGui_SameLine(ctx)
          if ig.ImGui_Button(ctx, S:t("ui.receive.close_cycle") .. "##close") then
            local ok, message = sess:close_cycle(lib.id, c.cycle)
            if not ok then sess.results[#sess.results + 1] = { ok = false, text = message } end
          end
        end
        ig.ImGui_PopID(ctx)
      end
    end
  end
  return action
end

return M
