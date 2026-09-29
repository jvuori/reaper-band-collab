-- In-memory file system with the same interface as lib/bandcollab/fs_std.lua, for tests.
-- Paths use "/" and directories exist implicitly.
local M = {}

function M.new(files)
  local fs = { files = files or {} }

  function fs.exists(path) return fs.files[path] ~= nil end
  function fs.size(path) return fs.files[path] and #fs.files[path] or nil end
  function fs.read_all(path)
    local d = fs.files[path]
    if d == nil then return nil, path .. ": no such file" end
    return d
  end
  function fs.write_all(path, data) fs.files[path] = data; return true end
  function fs.remove(path) local had = fs.files[path] ~= nil; fs.files[path] = nil; return had end
  function fs.rename(from, to)
    if fs.files[from] == nil then return false end
    fs.files[to], fs.files[from] = fs.files[from], nil
    return true
  end
  function fs.mkdirs() return true end

  function fs.open_read(path)
    local d = fs.files[path]
    if d == nil then return nil, path .. ": no such file" end
    local pos = 1
    return {
      read = function(_, n)
        if pos > #d then return nil end
        local chunk = d:sub(pos, pos + n - 1)
        pos = pos + #chunk
        return chunk
      end,
      close = function() end,
    }
  end

  function fs.list(dir)
    local prefix = dir:gsub("/+$", "") .. "/"
    local seen, out = {}, {}
    for path in pairs(fs.files) do
      if path:sub(1, #prefix) == prefix then
        local rest = path:sub(#prefix + 1)
        local name, tail = rest:match("^([^/]+)(/?)")
        if not seen[name] then
          seen[name] = true
          out[#out + 1] = { name = name, is_dir = tail == "/" }
        end
      end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
  end

  return fs
end

return M
