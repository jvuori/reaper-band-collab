-- Detects WAV files that were cut short (for example by an interrupted copy): the header of a
-- finished recording states how many audio bytes follow, so a file shorter than that is incomplete.
local M = {}

-- check(fs, path) -> "ok" | "empty" | "truncated" | "unknown"
--   "unknown" means the file is not a WAV we can judge (other formats are only checked for size 0).
function M.check(fs, path)
  local size = fs.size(path)
  if size == nil then return "unknown" end
  if size == 0 then return "empty" end
  if not path:lower():match("%.wav$") then return "unknown" end

  local head = fs.read_range(path, 0, 65536)
  if not head or #head < 12 or head:sub(1, 4) ~= "RIFF" or head:sub(9, 12) ~= "WAVE" then return "unknown" end

  local pos = 13
  while pos + 8 <= #head do
    local id = head:sub(pos, pos + 3)
    local len = string.unpack("<I4", head, pos + 4)
    if id == "data" then
      if len == 0 or len == 0xFFFFFFFF then return "unknown" end -- streamed or unfinished header
      if pos + 8 - 1 + len > size then return "truncated" end
      return "ok"
    end
    pos = pos + 8 + len + (len % 2)
  end
  return "unknown"
end

return M
