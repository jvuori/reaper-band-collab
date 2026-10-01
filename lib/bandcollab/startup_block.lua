-- The marked block the guardian keeps in REAPER's Scripts/__startup.lua. REAPER runs that file at
-- start-up (see docs/spikes/startup-hook.md); the block loads the guardian from where ReaPack put
-- it, so updates need no change here. Anything else in the file belongs to the user and is never touched.
local M = {}

M.BEGIN = "-- BEGIN bandcollab"
M.END = "-- END bandcollab"

local function block(script_path)
  return table.concat({
    M.BEGIN .. " (managed by Band Collab; remove it with \"Disable band guardian\")",
    "do",
    "  local ok, err = pcall(dofile, " .. string.format("%q", script_path) .. ")",
    "  if not ok then reaper.SetExtState(\"bandcollab\", \"guardian_error\", tostring(err), false) end",
    "end",
    M.END,
  }, "\n")
end

-- locate(text) -> first, last (character positions of the whole block, markers included) | nil
local function locate(text)
  local first = text:find(M.BEGIN, 1, true)
  if not first then return nil end
  local _, last = text:find(M.END, first, true)
  if not last then return nil end
  return first, last
end

function M.has(text) return locate(text) ~= nil end

-- remove(text) -> text without the block (and without the blank line that separated it)
function M.remove(text)
  local first, last = locate(text)
  if not first then return text end
  local before, after = text:sub(1, first - 1), text:sub(last + 1)
  before = before:gsub("\n\n$", "\n"):gsub("^\n$", "")
  after = after:gsub("^\n", "")
  return before .. after
end

-- install(text, script_path) -> text with exactly one block pointing at script_path
-- An existing block is replaced (so a new install location is picked up); other content is kept.
function M.install(text, script_path)
  text = M.remove(text)
  local separator = (text == "" or text:sub(-2) == "\n\n") and "" or (text:sub(-1) == "\n" and "\n" or "\n\n")
  return text .. separator .. block(script_path) .. "\n"
end

return M
