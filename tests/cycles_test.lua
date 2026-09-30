local t = require("luatest")
local cycles = require("bandcollab.cycles")
local receive = require("bandcollab.receive")
local messages = require("bandcollab.messages")
local strings = require("bandcollab.strings")
local memfs = require("memfs")

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" } },
  members = { { id = "aino", name = "Aino", roles = { "bass" } } },
  locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" },
  libraries = { { id = "harjoitukset", label = "Harjoitukset", kind = "dated" }, { id = "levytys", label = "Levytys", kind = "flat" } },
}
local rehearsals, official = band.libraries[1], band.libraries[2]
local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")

t.test("dates must be real calendar dates written year-month-day", function()
  for _, ok in ipairs({ "2026-09-29", "2024-02-29", "2000-02-29", "2026-12-31" }) do t.truthy(cycles.valid_date(ok), ok) end
  for _, bad in ipairs({ "2026-13-01", "2026-00-10", "2026-02-29", "1900-02-29", "2026-04-31", "26-09-29", "2026/09/29", "2026-9-29", "", "today" }) do
    t.falsy(cycles.valid_date(bad), bad)
  end
end)

t.test("a new cycle is created open in the producer's area and mirrored to the publications", function()
  local fs = memfs.new()
  local st = cycles.ensure(fs, band, "/band", rehearsals, "2026-09-29", "T1")
  t.eq(st.state, "open")
  t.truthy(fs.exists("/band/tuottaja/harjoitukset/2026-09-29/cycle.json"))
  t.truthy(fs.exists("/band/julkaisut/harjoitukset/2026-09-29/cycle.json"))
  local _, code = cycles.ensure(fs, band, "/band", rehearsals, "2026-99-99")
  t.eq(code, "bad_date")
end)

t.test("closing a cycle marks it closed in both areas, and ensure never reopens it", function()
  local fs = memfs.new()
  cycles.ensure(fs, band, "/band", rehearsals, "2026-09-29", "T1")
  t.truthy(cycles.close(fs, band, "/band", rehearsals, "2026-09-29", "T2"))
  local st = cycles.state(fs, band, "/band", rehearsals, "2026-09-29")
  t.eq(st.state, "closed"); t.eq(st.opened, "T1"); t.eq(st.closed, "T2")
  t.truthy(fs.files["/band/tuottaja/harjoitukset/2026-09-29/cycle.json"]:find("closed"))
  t.truthy(fs.files["/band/julkaisut/harjoitukset/2026-09-29/cycle.json"]:find("closed"))
  t.eq(cycles.ensure(fs, band, "/band", rehearsals, "2026-09-29", "T3").state, "closed")
end)

t.test("a proposal to a closed cycle is refused, with an explanation naming the cycle", function()
  local fs = memfs.new()
  cycles.ensure(fs, band, "/band", rehearsals, "2026-09-22", "T1")
  cycles.ensure(fs, band, "/band", rehearsals, "2026-09-29", "T1")
  cycles.close(fs, band, "/band", rehearsals, "2026-09-22", "T2")

  local ok, code, detail = cycles.check_open(fs, band, "/band", "harjoitukset", "2026-09-22")
  t.eq(ok, nil); t.eq(code, "cycle_closed"); t.eq(detail, "2026-09-22")
  local msg = messages.get(S, code, { detail = detail })
  t.truthy(msg.what:find("2026-09-22", 1, true))
  t.truthy(msg.what:find("suljettu"))
  t.truthy(msg.action:find("Kysy tuottajalta"))

  t.truthy(cycles.check_open(fs, band, "/band", "harjoitukset", "2026-09-29"), "the other cycle stays open")
end)

t.test("a member, who cannot see the producer's area, still sees that the cycle is closed", function()
  local fs = memfs.new()
  cycles.ensure(fs, band, "/band", rehearsals, "2026-09-29", "T1")
  cycles.close(fs, band, "/band", rehearsals, "2026-09-29", "T2")
  for path in pairs(fs.files) do if path:find("^/band/tuottaja/") then fs.files[path] = nil end end
  local ok, code = cycles.check_open(fs, band, "/band", "harjoitukset", "2026-09-29")
  t.eq(ok, nil); t.eq(code, "cycle_closed")
end)

t.test("flat libraries, unknown libraries and cycles nobody has heard of are open", function()
  local fs = memfs.new()
  t.truthy(cycles.check_open(fs, band, "/band", "levytys", nil))
  t.truthy(cycles.check_open(fs, band, "/band", "levytys", "2026-09-29"))
  t.truthy(cycles.check_open(fs, band, "/band", "nope", "2026-09-29"))
  t.truthy(cycles.check_open(fs, band, "/band", "harjoitukset", "2026-09-29"))
  t.truthy(cycles.check_open(fs, band, "/band", "harjoitukset", nil))
end)

t.test("closing something that does not exist gives a clear code", function()
  local fs = memfs.new()
  local _, c1 = cycles.close(fs, band, "/band", rehearsals, "2026-09-29")
  t.eq(c1, "cycle_unknown")
  local _, c2 = cycles.close(fs, band, "/band", official, "2026-09-29")
  t.eq(c2, "cycle_unknown")
  local _, c3 = cycles.close(fs, band, "/band", rehearsals, "nonsense")
  t.eq(c3, "bad_date")
end)

t.test("a closed cycle takes no new songs, but other dates still do", function()
  local fs = memfs.new()
  local function stage(dir, name)
    fs.files[dir .. "/" .. name .. ".rpp"] = "<REAPER_PROJECT 0.1 \"7.0\" 0\n>\n"
  end
  stage("/stage/a", "eka"); stage("/stage/b", "toka")
  local ctx = assert(receive.context(fs, band, "/band"))
  local list = receive.candidates(ctx, "/stage")
  t.truthy(receive.import(ctx, list[1], { library = "harjoitukset", cycle = "2026-09-29", now = "T" }))
  cycles.close(fs, band, "/band", rehearsals, "2026-09-29", "T2")
  local nothing, code, detail = receive.import(ctx, list[2], { library = "harjoitukset", cycle = "2026-09-29", now = "T" })
  t.eq(nothing, nil); t.eq(code, "cycle_closed"); t.eq(detail, "2026-09-29")
  t.falsy(fs.exists("/band/tuottaja/harjoitukset/2026-09-29/toka/toka.rpp"), "nothing may be written into a closed cycle")
  t.truthy(receive.import(ctx, list[2], { library = "harjoitukset", cycle = "2026-10-06", now = "T" }))
  local listing = cycles.list(fs, band, "/band", rehearsals)
  t.eq(listing[1].state, "closed"); t.eq(listing[2].state, "open")
end)

t.test("every outcome the receive step can produce has a message in both languages", function()
  local codes = { "cycle_closed", "cycle_unknown", "registry_invalid", "incomplete", "already_registered", "already_received",
    "copy_undecided", "bad_date", "unknown_library", "cannot_copy", "cannot_write" }
  for _, c in ipairs(codes) do
    for _, part in ipairs({ "what", "action" }) do
      t.truthy(S:has("err." .. c .. "." .. part, "fi"), "fi " .. c .. "." .. part)
      t.truthy(S:has("err." .. c .. "." .. part, "en"), "en " .. c .. "." .. part)
    end
  end
end)
