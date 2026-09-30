-- Copies a folder tree file by file in chunks, so large audio files never sit in memory whole
-- and a caller running in a coroutine can show progress.
local M = {}

M.CHUNK = 4 * 1024 * 1024

-- copy_file(fs, from, to [, yield]) -> bytes copied | nil, err
function M.copy_file(fs, from, to, yield)
  local src, err = fs.open_read(from)
  if not src then return nil, err end
  local dst, werr = fs.open_write(to)
  if not dst then src:close(); return nil, werr end
  local total = 0
  while true do
    local chunk = src:read(M.CHUNK)
    if not chunk or #chunk == 0 then break end
    dst:write(chunk)
    total = total + #chunk
    if yield then yield(total, from) end
  end
  src:close()
  dst:close()
  return total
end

-- copy(fs, from_dir, to_dir [, opts]) -> list of relative paths copied | nil, err
--   opts.skip(relative_path) -> true to leave a file out (only checked for files)
--   opts.yield(bytes_of_current_file, path)
-- Every copied file is checked against the size of its source.
function M.copy(fs, from_dir, to_dir, opts)
  opts = opts or {}
  local copied = {}
  local function walk(rel)
    local src_dir = rel == "" and from_dir or (from_dir .. "/" .. rel)
    local dst_dir = rel == "" and to_dir or (to_dir .. "/" .. rel)
    if not fs.mkdirs(dst_dir) then return nil, "cannot create " .. dst_dir end
    for _, e in ipairs(fs.list(src_dir) or {}) do
      local r = rel == "" and e.name or (rel .. "/" .. e.name)
      if e.is_dir then
        local ok, err = walk(r)
        if not ok then return nil, err end
      elseif not (opts.skip and opts.skip(r)) then
        local n, err = M.copy_file(fs, from_dir .. "/" .. r, to_dir .. "/" .. r, opts.yield)
        if not n then return nil, err end
        if fs.size(to_dir .. "/" .. r) ~= fs.size(from_dir .. "/" .. r) then return nil, "size differs after copying " .. r end
        copied[#copied + 1] = r
      end
    end
    return true
  end
  local ok, err = walk("")
  if not ok then return nil, err end
  return copied
end

return M
