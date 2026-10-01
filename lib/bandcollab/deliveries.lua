-- A member's deliveries (proposals). Each is a complete, frozen folder in the member's outbox,
-- named by the time it was made; a newer one supersedes older ones, which are kept.
local json = require("bandcollab.json")
local manifest = require("bandcollab.manifest")

local M = {}

M.SCHEMA = 1
M.INFO = "delivery.json"
M.IMPORTS = "imports.json" -- written by the producer into the publications song folder

-- new_id(epoch) -> "d20260929T204100Z" (UTC, no characters that some file systems refuse)
function M.new_id(epoch) return os.date("!d%Y%m%dT%H%M%SZ", epoch) end

-- unique_id(fs, outbox, epoch) -> an id not used in the outbox yet (two sends in one second get -2, -3, ...)
function M.unique_id(fs, outbox, epoch)
  local base = M.new_id(epoch)
  local taken = {}
  for _, e in ipairs(fs.list(outbox) or {}) do taken[e.name] = true end
  if not taken[base] then return base end
  local n = 2
  while taken[base .. "-" .. n] do n = n + 1 end
  return base .. "-" .. n
end

-- list(fs, outbox) -> { {id =, dir =, complete = bool}, ... } oldest first
function M.list(fs, outbox)
  local out = {}
  for _, e in ipairs(fs.list(outbox) or {}) do
    if e.is_dir and e.name:match("^d%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ") then
      local dir = outbox .. "/" .. e.name
      out[#out + 1] = { id = e.name, dir = dir, complete = fs.exists(dir .. "/" .. manifest.MARKER) }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- latest(fs, outbox) -> the newest complete delivery, or nil
function M.latest(fs, outbox)
  local latest
  for _, d in ipairs(M.list(fs, outbox)) do if d.complete then latest = d end end
  return latest
end

-- read(fs, dir) -> the delivery.json of a delivery, or nil
function M.read(fs, dir)
  local info = json.try_decode(fs.read_all(dir .. "/" .. M.INFO) or "")
  if type(info) ~= "table" then return nil end
  return info
end

-- status(fs, publications_song_dir, delivery_id) -> "accepted" | "pending"
-- The producer records what it has taken into the master in imports.json (a missing file means
-- nothing has been taken in yet).
function M.status(fs, publications_song_dir, delivery_id)
  local data = json.try_decode(fs.read_all(publications_song_dir .. "/" .. M.IMPORTS) or "")
  if type(data) == "table" and type(data.imports) == "table" then
    for _, item in ipairs(data.imports) do
      if item.delivery == delivery_id then return "accepted", item end
    end
  end
  return "pending"
end

return M
