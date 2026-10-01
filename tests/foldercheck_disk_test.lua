-- The folder check against a band folder built by the real tools (REAPER only): a healthy one must
-- report nothing, or people learn to ignore it.
local t = require("luatest")
local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

local F = require("reaper_fixture")
local band, published, cleanup, NOW = F.band, F.published, F.cleanup, F.NOW

t.test("a band folder after publishing, a workspace, a proposal and an import reports nothing", function()
  need_reaper()
  local foldercheck, workspace, sync = require("bandcollab.foldercheck"), require("bandcollab.workspace"), require("bandcollab.workspace_sync")
  local importer, inbox, projects, pm = require("bandcollab.importer"), require("bandcollab.inbox"), require("bandcollab.projects"), require("bandcollab.projectmodel")
  local fx, song, S = published()
  local ws = assert(workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW }))
  local item = reaper.GetTrackMediaItem(reaper.GetTrack(ws.proj, pm.role_folders(ws.proj)[2].index), 0)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0.4)
  projects.save_bound(ws.proj)
  assert(sync.send(fx.fs, band, fx.band_folder, ws, { note = { summary = "x" }, epoch = 1000000, now = NOW }))
  projects.close_tab(ws.proj)
  local master = assert(importer.identify_master(fx.fs, fx.proj))
  assert(importer.import(fx.fs, band, fx.band_folder, master, inbox.list(fx.fs, band, fx.band_folder).pending[1], S, { epoch = 2000000, now = NOW }))

  local problems, tidy = foldercheck.split(foldercheck.check(fx.fs, band, fx.band_folder))
  for _, p in ipairs(tidy) do t.eq(p.code, "stray_file", "only harmless leftovers (REAPER's peak files and autosaves) may be reported")  end
  local lines = {}
  for _, p in ipairs(problems) do lines[#lines + 1] = p.code .. " " .. p.path .. " " .. tostring(p.detail) end
  t.eq(#problems, 0, "false alarms on a healthy folder: " .. table.concat(lines, " | "))

  -- and a real fault is still found on the same folder
  fx.fs.write_all(fx.band_folder .. "/publications/rehearsals/2026-09-29/" .. song.slug .. "/notes.rpp", "<REAPER_PROJECT>")
  fx.fs.write_all(fx.band_folder .. "/producer/stray.reapeaks", "x")
  local codes = {}
  for _, p in ipairs(foldercheck.check(fx.fs, band, fx.band_folder)) do codes[p.code] = true end
  t.truthy(codes.wrong_area); t.truthy(codes.stray_file)
  cleanup(fx)
end)
