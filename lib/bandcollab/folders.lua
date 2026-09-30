-- Folder-track nesting, computed from REAPER's I_FOLDERDEPTH values.
-- `depths` is an array (1-based) with one value per track, in project order:
--   1  = starts a folder    0 = ordinary track    -n = last track inside n nested folders
local M = {}

-- span(depths, first) -> index of the last track inside the folder that starts at `first`.
-- Returns `first` when that track does not start a folder; an unclosed folder runs to the end.
function M.span(depths, first)
  local d = depths[first]
  if d == nil or d <= 0 then return first end
  local level = d
  for i = first + 1, #depths do
    level = level + depths[i]
    if level <= 0 then return i end
  end
  return #depths
end

-- top_level(depths) -> list of { first =, last = } for every folder that is not inside another.
function M.top_level(depths)
  local out, i = {}, 1
  while i <= #depths do
    if depths[i] > 0 then
      local last = M.span(depths, i)
      out[#out + 1] = { first = i, last = last }
      i = last + 1
    else
      i = i + 1
    end
  end
  return out
end

-- inside(depths, first) -> list of track indices inside the folder starting at `first`
function M.inside(depths, first)
  local out = {}
  for i = first + 1, M.span(depths, first) do out[#out + 1] = i end
  return out
end

-- folder_of(depths, index) -> { first =, last = } of the top-level folder containing the track, or nil
function M.folder_of(depths, index)
  for _, f in ipairs(M.top_level(depths)) do
    if index >= f.first and index <= f.last then return f end
  end
  return nil
end

return M
