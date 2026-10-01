-- The guardian looking at real project tabs in REAPER (run through tests/reaper_runner.lua).
local t = require("luatest")
local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

local F = require("reaper_fixture")
local band, published, republish, cleanup, NOW = F.band, F.published, F.republish, F.cleanup, F.NOW

local function modules()
  return require("bandcollab.guardian_runtime"), require("bandcollab.guardian_reaper"), require("bandcollab.workspace"),
    require("bandcollab.projects"), require("bandcollab.guardian"), require("bandcollab.copytree")
end

local function alert_for(alerts, file)
  for _, a in ipairs(alerts) do if a.file == file then return a end end
end

local function codes(alert)
  local out = {}
  for _, w in ipairs(alert and alert.warnings or {}) do out[#out + 1] = w.code .. ":" .. w.severity end
  return table.concat(out, ",")
end

-- master open, Eero's workspace open, and a plain project of Eero's own open
local function scene()
  local runtime, greaper, workspace, projects = modules()
  local fx, song, S = published()
  local ws = assert(workspace.create(fx.fs, band, fx.band_folder, "eero", song, { now = NOW }))
  local plain_dir = fx.root .. "/my-demo"
  fx.fs.mkdirs(plain_dir)
  fx.fs.write_all(plain_dir .. "/demo.rpp", '<REAPER_PROJECT 0.1 "7.0" 0\n>\n')
  local plain = projects.open_bound(plain_dir .. "/demo.rpp")
  return fx, song, S, ws, plain_dir .. "/demo.rpp", plain
end

local function finish(fx, ws, plain)
  local _, _, _, projects = modules()
  if plain then projects.close_tab(plain) end
  if ws then projects.close_tab(ws.proj) end
  cleanup(fx)
end

t.test("as a member, opening the master warns; his own workspace and an ordinary project do not", function()
  need_reaper()
  local runtime, greaper = modules()
  local fx, _, _, ws, plain_file, plain = scene()
  local rt = runtime.new(fx.fs, band, fx.band_folder, "eero")
  local alerts = rt:scan(greaper.projects())

  local master_file = F.master_file_of and F.master_file_of(fx) or fx.master_file
  t.eq(codes(alert_for(alerts, fx.master_file)), "master:strong", "the master must be flagged for a member")
  t.eq(alert_for(alerts, ws.file), nil, "his own, current workspace is fine")
  t.eq(alert_for(alerts, plain_file), nil, "an ordinary project is never mentioned")
  local logged = fx.fs.read_all(fx.band_folder .. "/proposals/eero/guardian.log")
  t.truthy(logged and logged:find("master", 1, true), "the event is logged")
  finish(fx, ws, plain)
end)

t.test("the producer opening the master is not warned", function()
  need_reaper()
  local runtime, greaper = modules()
  local fx, _, _, ws, _, plain = scene()
  local alerts = runtime.new(fx.fs, band, fx.band_folder, "aino"):scan(greaper.projects())
  t.eq(alert_for(alerts, fx.master_file), nil)
  -- but Eero's workspace is not the producer's
  t.eq(codes(alert_for(alerts, ws.file)), "other_workspace:strong")
  finish(fx, ws, plain)
end)

t.test("each warning is shown once per open, with real tabs, and again after reopening", function()
  need_reaper()
  local runtime, greaper, _, projects = modules()
  local fx, _, _, ws, _, plain = scene()
  local rt = runtime.new(fx.fs, band, fx.band_folder, "pia")
  t.truthy(alert_for(rt:scan(greaper.projects()), ws.file))
  for _ = 1, 3 do t.eq(alert_for(rt:scan(greaper.projects()), ws.file), nil, "no repeat while it stays open") end
  local file = ws.file
  projects.close_tab(ws.proj)
  rt:scan(greaper.projects())                                   -- the guardian notices it is gone
  local again = projects.open_bound(file)
  t.truthy(alert_for(rt:scan(greaper.projects()), file), "reopened: warned again")
  projects.close_tab(again)
  finish(fx, nil, plain)
end)

t.test("a workspace of a closed cycle is flagged; one based on an older master gets a gentle notice", function()
  need_reaper()
  local runtime, greaper = modules()
  local cycles, bandfile = require("bandcollab.cycles"), require("bandcollab.bandfile")
  local fx, _, S, ws, _, plain = scene()

  republish(fx, S)                                              -- the master moves on to r2
  local rt = runtime.new(fx.fs, band, fx.band_folder, "eero")
  t.eq(codes(alert_for(rt:scan(greaper.projects()), ws.file)), "outdated:soft", "only a gentle notice: it must not be a blocking one")

  cycles.close(fx.fs, band, fx.band_folder, bandfile.library(band, "rehearsals"), "2026-09-29")
  local rt2 = runtime.new(fx.fs, band, fx.band_folder, "eero")
  local result = codes(alert_for(rt2:scan(greaper.projects()), ws.file))
  t.truthy(result:find("closed_cycle:warning"), "closed cycle: " .. result)
  finish(fx, ws, plain)
end)

t.test("a copy of the workspace saved elsewhere is reported as not being in its place", function()
  need_reaper()
  local runtime, greaper, _, projects, _, copytree = modules()
  local fx, _, _, ws, _, plain = scene()
  local copy_dir = fx.root .. "/desktop/work"
  assert(copytree.copy(fx.fs, ws.dir .. "/work", copy_dir))
  local copy_file = copy_dir .. "/" .. ws.file:match("[^/]*$")
  local copy = projects.open_bound(copy_file)

  local rt = runtime.new(fx.fs, band, fx.band_folder, "eero")
  local alert = alert_for(rt:scan(greaper.projects()), copy_file)
  t.truthy(alert, "a misplaced workspace must be noticed")
  t.eq(alert.warnings[1].code, "misplaced")
  t.eq(alert.warnings[1].vars.where, ws.file, "it says where the workspace belongs")
  projects.close_tab(copy)
  finish(fx, ws, plain)
end)

t.test("a workspace saved as a lone file elsewhere is recognized by its hidden marker", function()
  need_reaper()
  local runtime, greaper, _, projects = modules()
  local pm = require("bandcollab.projectmodel")
  local fx, _, _, ws, _, plain = scene()
  local lone_dir = fx.root .. "/lone"
  fx.fs.mkdirs(lone_dir)
  fx.fs.write_all(lone_dir .. "/biisi.rpp", '<REAPER_PROJECT 0.1 "7.0" 0\n>\n')
  local lone = projects.open_bound(lone_dir .. "/biisi.rpp")
  pm.set_project_marker(lone, pm.KEY_KIND, "workspace")
  projects.save_bound(lone)
  projects.close_tab(lone)
  lone = projects.open_bound(lone_dir .. "/biisi.rpp")           -- as someone double-clicking it later

  local rt = runtime.new(fx.fs, band, fx.band_folder, "eero")
  local alert = alert_for(rt:scan(greaper.projects()), lone_dir .. "/biisi.rpp")
  t.truthy(alert); t.eq(alert.warnings[1].code, "misplaced_unknown")
  projects.close_tab(lone)
  finish(fx, ws, plain)
end)
