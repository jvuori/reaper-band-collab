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

-- title(text) -> the project's title (a TITLE line at project level, at most two spaces of
-- indentation, so titles of tracks or items further in are not mistaken for it), or nil.
function M.title(text)
  for line in text:gmatch("[^\r\n]+") do
    local indent, rest = line:match("^(%s*)TITLE%s+(.+)$")
    if rest and #indent <= 2 then
      local q = rest:sub(1, 1)
      if q == '"' or q == "'" or q == "`" then
        local title = rest:match("^" .. q .. "(.-)" .. q)
        if title and title ~= "" then return title end
      else
        local title = rest:match("^(%S+)")
        if title then return title end
      end
    end
  end
  return nil
end

-- rewrite_media(text, map) -> text with each FILE path found in `map` replaced by its new path.
-- Quoting, indentation and everything else on the line stay as they were.
function M.rewrite_media(text, map)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local indent, space, rest = line:match("^(%s*)FILE(%s+)(.+)$")
    if rest then
      local q = rest:sub(1, 1)
      local quoted = q == '"' or q == "'" or q == "`"
      local path, tail
      if quoted then path, tail = rest:match("^" .. q .. "(.-)" .. q .. "(.*)$") else path, tail = rest:match("^(%S+)(.*)$") end
      if path and map[path] then
        local nq = quoted and q or '"'
        line = indent .. "FILE" .. space .. nq .. map[path] .. nq .. tail
      end
    end
    out[#out + 1] = line
  end
  return table.concat(out, "\n")
end

-- is_absolute(path) -> true for "/x", "C:\x", "C:/x" and "\\server\share"
function M.is_absolute(path)
  return path:match("^[/\\]") ~= nil or path:match("^%a:[/\\]") ~= nil
end

return M
