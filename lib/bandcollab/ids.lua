-- Song IDs: opaque, unique, independent of where a song lives.
local M = {}

-- generate(taken [, rng]) -> "s" followed by 16 hex digits, not in the `taken` set.
-- rng(lo, hi) defaults to math.random; tests pass a fixed generator.
function M.generate(taken, rng)
  rng = rng or math.random
  taken = taken or {}
  while true do
    local id = string.format("s%08x%08x", rng(0, 0xFFFFFFFF), rng(0, 0xFFFFFFFF))
    if not taken[id] then return id end
  end
end

function M.valid(id) return type(id) == "string" and id:match("^s%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil end

return M
