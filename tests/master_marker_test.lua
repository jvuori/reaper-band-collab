-- The visible master banner, checked the way a person without the extension would see it (REAPER only).
local t = require("luatest")
local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

local F = require("reaper_fixture")
local band, published, cleanup, NOW = F.band, F.published, F.cleanup, F.NOW

t.test("the master carries a visible banner region at its start and a distinctive file name", function()
  need_reaper()
  local master_marker, receive = require("bandcollab.master_marker"), require("bandcollab.receive")
  local projects, pm = require("bandcollab.projects"), require("bandcollab.projectmodel")
  local fs = require("bandcollab.fs_std")
  local strings = require("bandcollab.strings")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")
  local fx = F.fixture()                        -- a registered master (received without a prefix)
  local banner = S:t("master.marker")

  -- a fresh receive with the prefix, then the banner, as the receive panel does it
  local stage = fx.root .. "/stage2/uusi"
  fs.mkdirs(stage .. "/media")
  fs.write_all(stage .. "/uusi.rpp", '<REAPER_PROJECT 0.1 "7.0" 0\n>\n')
  local ctx = assert(receive.context(fs, band, fx.band_folder))
  local cand
  for _, c in ipairs(receive.candidates(ctx, fx.root .. "/stage2")) do cand = c end
  local entry = assert(receive.import(ctx, cand, { library = "rehearsals", cycle = "2026-09-30", master_prefix = S:t("master.file_prefix") }))
  local file = fx.band_folder .. "/" .. entry.path .. "/" .. S:t("master.file_prefix") .. "_" .. entry.slug .. ".rpp"
  t.truthy(fs.exists(file)); t.truthy(file:find("PAAVERSIO_", 1, true))
  t.truthy(master_marker.ensure(fs, file, banner))

  -- what is in the project file itself: plain REAPER data, no extension involved
  local text = fs.read_all(file)
  t.truthy(text:find("PÄÄVERSIO", 1, true), "the banner text is written into the project file")
  t.truthy(text:find("9999", 1, true), "under its reserved number")

  -- opened with nothing but REAPER's own API: a region starting at 0:00
  local proj = projects.open_bound(file)
  local found
  local i = 0
  while true do
    local ret, is_region, pos, region_end, name, number = reaper.EnumProjectMarkers2(proj, i)
    if not ret or ret == 0 then break end
    if name == banner then found = { region = is_region, pos = pos, finish = region_end, number = number } end
    i = i + 1
  end
  t.truthy(found, "the banner must be visible among the project's own markers")
  t.truthy(found.region); t.eq(found.pos, 0.0); t.truthy(found.finish >= 1); t.eq(found.number, 9999)
  projects.close_tab(proj)

  -- doing it again does not add a second banner
  t.truthy(master_marker.ensure(fs, file, banner))
  local again = projects.open_bound(file)
  local count = 0
  i = 0
  while true do
    local ret, _, _, _, _, number = reaper.EnumProjectMarkers2(again, i)
    if not ret or ret == 0 then break end
    if number == 9999 then count = count + 1 end
    i = i + 1
  end
  t.eq(count, 1)
  projects.close_tab(again)
  cleanup(fx)
end)

t.test("the banner is not mistaken for a section of the song: it never shows up in the timing or a workspace", function()
  need_reaper()
  local master_marker, publisher = require("bandcollab.master_marker"), require("bandcollab.publisher")
  local fs = require("bandcollab.fs_std")
  local fx, song, S = published()
  t.truthy(master_marker.ensure(fs, fx.master_file, "PÄÄVERSIO - testi"))
  reaper.SelectProjectInstance(fx.proj)
  reaper.Main_openProject("noprompt:" .. fx.master_file)           -- reload the master with its banner
  local timing = publisher.capture_timing((reaper.EnumProjects(-1)))
  for _, m in ipairs(timing.markers) do t.truthy(m.name ~= "PÄÄVERSIO - testi", "the banner must not be captured as a section") end
  cleanup(fx)
end)
