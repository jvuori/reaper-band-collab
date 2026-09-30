-- File-system adapter used at run time. Same interface as tests/memfs.lua, so logic that takes
-- an `fs` argument can be tested without touching the disk.
--   fs.exists(path) -> bool             fs.size(path) -> integer | nil
--   fs.open_read(path) -> handle | nil, err   (handle:read(n), handle:close())
--   fs.read_all(path) -> string | nil, err    fs.write_all(path, data) -> true | nil, err
--   fs.open_write(path) -> handle | nil, err  (handle:write(data), handle:close())
--   fs.read_range(path, offset, n) -> string | nil, err
--   fs.list(dir) -> { {name=, is_dir=}, ... } | nil    fs.mkdirs(path) -> bool
--   fs.remove(path) -> bool             fs.rename(from, to) -> bool
local M = {}

function M.exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

function M.size(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local n = f:seek("end")
  f:close()
  return n
end

function M.open_read(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  return f
end

-- open_write(path) -> handle | nil, err   (handle:write(data), handle:close()); creates or truncates.
function M.open_write(path)
  local f, err = io.open(path, "wb")
  if not f then return nil, err end
  return f
end

-- read_range(path, offset, n) -> string | nil, err   (offset is 0-based; may return fewer bytes at the end)
function M.read_range(path, offset, n)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  f:seek("set", offset)
  local s = f:read(n) or ""
  f:close()
  return s
end

function M.read_all(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local s = f:read("a")
  f:close()
  return s
end

function M.write_all(path, data)
  local f, err = io.open(path, "wb")
  if not f then return nil, err end
  f:write(data)
  f:close()
  return true
end

function M.remove(path) return os.remove(path) and true or false end
function M.rename(from, to) return os.rename(from, to) and true or false end

local function shquote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

if reaper then
  function M.list(dir)
    -- REAPER caches directory listings per path; index -1 flushes the cache, so a listing
    -- always reflects what is on disk now (files and folders created since the last listing).
    reaper.EnumerateSubdirectories(dir, -1)
    reaper.EnumerateFiles(dir, -1)
    local out = {}
    local i = 0
    while true do
      local name = reaper.EnumerateSubdirectories(dir, i)
      if not name then break end
      out[#out + 1] = { name = name, is_dir = true }
      i = i + 1
    end
    i = 0
    while true do
      local name = reaper.EnumerateFiles(dir, i)
      if not name then break end
      out[#out + 1] = { name = name, is_dir = false }
      i = i + 1
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
  end

  function M.mkdirs(path) return reaper.RecursiveCreateDirectory(path, 0) ~= 0 or M.exists(path) end
else
  -- Plain Lua (development and tests on Linux/macOS): shell out for directory operations.
  function M.list(dir)
    local p = io.popen("ls -1Ap " .. shquote(dir) .. " 2>/dev/null")
    if not p then return nil end
    local out = {}
    for line in p:lines() do
      local is_dir = line:sub(-1) == "/"
      out[#out + 1] = { name = is_dir and line:sub(1, -2) or line, is_dir = is_dir }
    end
    p:close()
    return out
  end

  function M.mkdirs(path) return os.execute("mkdir -p " .. shquote(path)) == true end
end

return M
