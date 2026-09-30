-- The track layout a band template gets, computed from band.json: one folder per role,
-- holding one or more ordinary tracks. Pure logic; projectmodel.lua applies it in REAPER.
local bandfile = require("bandcollab.bandfile")

local M = {}

-- Distinct, readable colours (r, g, b); roles cycle through them.
M.PALETTE = {
  { 214, 96, 77 }, { 67, 147, 195 }, { 102, 166, 30 }, { 230, 171, 2 },
  { 153, 112, 193 }, { 27, 158, 119 }, { 231, 138, 195 }, { 141, 160, 203 },
}

-- plan(band [, counts]) -> list of entries, in project order
--   counts: role id -> number of tracks inside that role's folder (default 1, minimum 1)
-- entry: { kind = "folder" | "track", name, role, owner (folders only), depth, color = {r,g,b} }
function M.plan(band, counts)
  counts = counts or {}
  local entries = {}
  for i, role in ipairs(band.roles) do
    local color = M.PALETTE[(i - 1) % #M.PALETTE + 1]
    local owner = bandfile.owner_of(band, role.id)
    local n = math.max(1, math.floor(counts[role.id] or 1))
    entries[#entries + 1] = {
      kind = "folder",
      name = owner and (role.label .. " - " .. owner.name) or role.label,
      role = role.id,
      owner = owner and owner.id or nil,
      depth = 1,
      color = color,
    }
    for k = 1, n do
      entries[#entries + 1] = {
        kind = "track",
        name = n == 1 and role.label or (role.label .. " " .. k),
        role = role.id,
        depth = (k == n) and -1 or 0,
        color = color,
      }
    end
  end
  return entries
end

-- depths(plan) -> array of folder depths, for the folders module
function M.depths(plan)
  local out = {}
  for i, e in ipairs(plan) do out[i] = e.depth end
  return out
end

return M
