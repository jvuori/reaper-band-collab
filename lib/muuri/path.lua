-- Path helpers that never hard-code a separator. Inside packs, paths are stored with "/"
-- and converted to the platform separator only when touching the file system.
local M = {}

M.WINDOWS_LIMIT = 260

-- The platform separator: from Lua's own configuration ("\" on Windows, "/" elsewhere).
function M.native_sep() return package.config:sub(1, 1) end

-- Converts every separator in a path to `sep`, collapsing repeats (except a leading UNC "\\").
function M.normalize(path, sep)
  sep = sep or M.native_sep()
  local unc = path:match("^[/\\][/\\]") and sep .. sep or ""
  local body = unc ~= "" and path:sub(3) or path
  body = body:gsub("[/\\]+", sep)
  return unc .. body
end

-- join(sep, a, b, ...) joins segments with exactly one separator between them.
function M.join(sep, first, ...)
  local acc = first
  for _, part in ipairs({ ... }) do
    if part ~= "" then
      acc = acc:gsub("[/\\]+$", "") .. sep .. part:gsub("^[/\\]+", "")
    end
  end
  return M.normalize(acc, sep)
end

function M.basename(path) return path:match("([^/\\]*)[/\\]*$") end

function M.dirname(path)
  local d = path:gsub("[/\\]+$", ""):match("^(.*)[/\\][^/\\]*$")
  return d or ""
end

-- relative(root, path) -> path below root using "/", or nil when path is not inside root.
function M.relative(root, path)
  local r = root:gsub("\\", "/"):gsub("/+$", "")
  local p = path:gsub("\\", "/")
  if p:sub(1, #r + 1) ~= r .. "/" then return nil end
  return p:sub(#r + 2)
end

-- too_long(path [, limit]) -> true when the path would exceed the Windows path limit.
function M.too_long(path, limit) return #path >= (limit or M.WINDOWS_LIMIT) end

return M
