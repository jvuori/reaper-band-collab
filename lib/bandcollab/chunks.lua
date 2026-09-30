-- REAPER track state chunks: the text REAPER uses to describe one track with its items.
-- A published role folder is stored as several chunks in one file (tracks.chunk).
local M = {}

-- split(text) -> list of chunk strings, one per top-level <TRACK ...> block, in order.
-- Blocks nest (<TRACK> holds <ITEM>, <SOURCE>, <FXCHAIN>...), so the end of a track is found by
-- counting block openings and closings, whatever the indentation.
function M.split(text)
  local out, current, depth = {}, nil, 0
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    if not current then
      if line:match("^%s*<TRACK") then current, depth = { line }, 1 end
    else
      current[#current + 1] = line
      if line:match("^%s*<%u") then depth = depth + 1
      elseif line:match("^%s*>%s*$") then depth = depth - 1 end
      if depth == 0 then
        out[#out + 1] = table.concat(current, "\n") .. "\n"
        current = nil
      end
    end
  end
  return out
end

return M
