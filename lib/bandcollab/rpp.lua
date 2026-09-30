-- Reads what we need from a REAPER project file (plain text): the media files it refers to.
local M = {}

-- media_refs(text) -> list of file paths named by FILE lines, in order, without duplicates.
-- REAPER writes `FILE "path"`; paths containing double quotes use single quotes or backticks.
function M.media_refs(text)
  local out, seen = {}, {}
  for line in text:gmatch("[^\r\n]+") do
    local rest = line:match("^%s*FILE%s+(.+)$")
    if rest then
      local q = rest:sub(1, 1)
      local path
      if q == '"' or q == "'" or q == "`" then
        path = rest:match("^" .. q .. "(.-)" .. q)
      else
        path = rest:match("^(%S+)")
      end
      if path and path ~= "" and not seen[path] then
        seen[path] = true
        out[#out + 1] = path
      end
    end
  end
  return out
end

-- is_absolute(path) -> true for "/x", "C:\x", "C:/x" and "\\server\share"
function M.is_absolute(path)
  return path:match("^[/\\]") ~= nil or path:match("^%a:[/\\]") ~= nil
end

return M
