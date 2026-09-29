-- @description Hello-world ReaImGui window (spike 1.5)
-- @version 0.0.1
-- Shows a small window for a few seconds and logs what happened, so an automated
-- run can verify it. Set HELLO_OUT to a file path to write the log and quit REAPER.
local out_path = os.getenv("HELLO_OUT")
local log = {}
local function w(...) log[#log + 1] = string.format(...) end

if not reaper.APIExists("ImGui_CreateContext") then
  w("ReaImGui NOT available")
else
  local ctx = reaper.ImGui_CreateContext("Muuri hello")
  local frames, visible_frames = 0, 0
  local function loop()
    reaper.ImGui_SetNextWindowSize(ctx, 320, 120, reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_Begin(ctx, "Muuri", true)
    frames = frames + 1
    if visible then
      visible_frames = visible_frames + 1
      reaper.ImGui_Text(ctx, "Hei! ReaImGui toimii.")
      reaper.ImGui_End(ctx)
    end
    if open and (not out_path or frames < 120) then
      reaper.defer(loop)
    else
      w("frames=%d visible_frames=%d", frames, visible_frames)
      if out_path then
        local f = io.open(out_path, "w"); f:write(table.concat(log, "\n"), "\n"); f:close()
        reaper.Main_OnCommand(40004, 0)
      end
    end
  end
  w("ReaImGui context created")
  reaper.defer(loop)
  return
end
if out_path then
  local f = io.open(out_path, "w"); f:write(table.concat(log, "\n"), "\n"); f:close()
  reaper.Main_OnCommand(40004, 0)
end
