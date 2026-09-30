-- Run inside REAPER by tools/scp_e2e.sh: receives a rehearsal that arrived through a real scp.
-- Env: BANDCOLLAB_ROOT, PHASE (1 = report only, 2 = import what is ready), INCOMING, BAND_FOLDER, OUT
local root = assert(os.getenv("BANDCOLLAB_ROOT"))
package.path = table.concat({ root .. "/lib/?.lua", package.path }, ";")
local fs = require("bandcollab.fs_std")
local bandfile = require("bandcollab.bandfile")
local receive = require("bandcollab.receive")

local phase, incoming, band_folder, out = os.getenv("PHASE"), os.getenv("INCOMING"), os.getenv("BAND_FOLDER"), os.getenv("OUT")
local lines = {}
local function w(...) lines[#lines + 1] = string.format(...) end

if not fs.exists(band_folder .. "/band.json") then
  fs.mkdirs(band_folder)
  for _, d in ipairs({ "producer", "publications", "proposals" }) do fs.mkdirs(band_folder .. "/" .. d) end
  assert(bandfile.write(fs, band_folder, {
    schema = 1, name = "Example Band", language = "en", producer = "aino",
    roles = { { id = "bass", label = "Bass" } }, members = { { id = "aino", name = "Aino", roles = { "bass" } } },
    locations = { master = "producer", publications = "publications", proposals = "proposals" },
  }))
end
local band = assert(bandfile.read(fs, band_folder))
local ctx = assert(receive.context(fs, band, band_folder))
local list = receive.candidates(ctx, incoming)
w("phase %s: %d songs found", phase, #list)
for _, c in ipairs(list) do
  local problems = {}
  for _, p in ipairs(c.inspection.problems) do problems[#problems + 1] = p.code .. " " .. p.path end
  w("  %-12s selectable=%-5s state=%-8s %s", c.name, tostring(c.selected), c.identity.state, table.concat(problems, "; "))
  if phase == "2" and c.selected then
    local entry, code, detail = receive.import(ctx, c, { cycle = "2026-09-29" })
    w("    -> %s", entry and ("received as " .. entry.path) or ("refused: " .. tostring(code) .. " " .. tostring(detail)))
  end
end
local f = io.open(out, "w"); f:write(table.concat(lines, "\n"), "\n"); f:close()
reaper.Main_OnCommand(40004, 0)
