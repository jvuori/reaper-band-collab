-- Numbered publications (r1, r2, ...). A revision is COMPLETE once it holds the completion
-- marker, and a complete revision is never written to again: a new publish always makes a new
-- number. A directory without the marker is the leftover of an interrupted publish and is reused.
local manifest = require("bandcollab.manifest")

local M = {}

function M.dir(pub_dir, number) return pub_dir .. "/r" .. number end

-- list(fs, pub_dir) -> { {number =, dir =, complete = bool}, ... } sorted by number
function M.list(fs, pub_dir)
  local out = {}
  for _, e in ipairs(fs.list(pub_dir) or {}) do
    local n = e.is_dir and e.name:match("^r([1-9]%d*)$")
    if n then
      local dir = pub_dir .. "/" .. e.name
      out[#out + 1] = { number = tonumber(n), dir = dir, complete = fs.exists(dir .. "/" .. manifest.MARKER) }
    end
  end
  table.sort(out, function(a, b) return a.number < b.number end)
  return out
end

-- latest(fs, pub_dir) -> the newest complete revision, or nil
function M.latest(fs, pub_dir)
  local latest
  for _, r in ipairs(M.list(fs, pub_dir)) do if r.complete then latest = r end end
  return latest
end

-- clear(fs, dir) -> number of files removed (folders stay, empty)
local function clear(fs, dir)
  local removed = 0
  for _, e in ipairs(fs.list(dir) or {}) do
    local p = dir .. "/" .. e.name
    if e.is_dir then removed = removed + clear(fs, p)
    elseif fs.remove(p) then removed = removed + 1 end
  end
  return removed
end

-- next(fs, pub_dir) -> number, dir, removed
-- The number for the next publish. A leftover incomplete directory with the highest number is
-- emptied and reused; otherwise the next number after the highest one is used.
function M.next(fs, pub_dir)
  local all = M.list(fs, pub_dir)
  local last = all[#all]
  if not last then return 1, M.dir(pub_dir, 1), 0 end
  if not last.complete then return last.number, last.dir, clear(fs, last.dir) end
  return last.number + 1, M.dir(pub_dir, last.number + 1), 0
end

-- writable(fs, dir) -> true | nil, "revision_complete": guards every write into a revision folder
function M.writable(fs, dir)
  if fs.exists(dir .. "/" .. manifest.MARKER) then return nil, "revision_complete" end
  return true
end

return M
