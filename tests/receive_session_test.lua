local t = require("luatest")
local session = require("bandcollab.receive_session")
local strings = require("bandcollab.strings")
local memfs = require("memfs")

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" } },
  members = { { id = "aino", name = "Aino", roles = { "bass" } }, { id = "eero", name = "Eero", roles = { "bass" } } },
  locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" },
  libraries = { { id = "harjoitukset", label = "Harjoitukset", kind = "dated" }, { id = "levytys", label = "Levytys", kind = "flat" } },
}
band.members[2].roles = {}
band.roles[2] = { id = "keys", label = "Koskettimet" }
band.members[2].roles = { "keys" }

local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")

local function wav(n)
  local body = "WAVE" .. "fmt " .. string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, 48000, 96000, 2, 16) .. "data" .. string.pack("<I4", n) .. ("\1"):rep(n)
  return "RIFF" .. string.pack("<I4", #body) .. body
end
local function stage(fs, dir, name, size)
  fs.files[dir .. "/" .. name .. ".rpp"] = "<REAPER_PROJECT 0.1 \"7.0\" 0\n  <ITEM\n    <SOURCE WAVE\n      FILE \"media/" .. name .. ".wav\"\n    >\n  >\n>\n"
  fs.files[dir .. "/media/" .. name .. ".wav"] = wav(size or 300)
end
local function drive(s) local n = 0; while not s:step() do n = n + 1; assert(n < 10000) end; return n end

t.test("only the producer can open the receive session", function()
  local sess, code = session.new(memfs.new(), band, "/band", S, "eero")
  t.eq(sess, nil); t.eq(code, "not_producer")
  t.truthy(session.new(memfs.new(), band, "/band", S, "aino"))
end)

t.test("rows show what was found: ready, problem, and already received", function()
  local fs = memfs.new()
  stage(fs, "/stage/a", "eka"); stage(fs, "/stage/b", "toka", 4000); stage(fs, "/stage/c", "kolmas")
  fs.files["/stage/b/media/toka.wav"] = fs.files["/stage/b/media/toka.wav"]:sub(1, 1000)
  local s = session.new(fs, band, "/band", S, "aino")
  t.eq(s:scan("/stage"), 3)
  t.eq(s.rows[1].status.kind, "ok"); t.truthy(s.rows[1].selected)
  t.eq(s.rows[2].status.kind, "problem"); t.falsy(s.rows[2].selected); t.falsy(s:can_select(s.rows[2]))
  t.truthy(s.rows[2].status.text:find("katkennut"))
  t.eq(#s:ready_rows(), 2)
end)

t.test("receiving runs in slices and reports each song", function()
  local fs = memfs.new()
  stage(fs, "/stage/a", "eka", 2000); stage(fs, "/stage/b", "toka", 2000)
  local s = session.new(fs, band, "/band", S, "aino")
  s:scan("/stage")
  s.library, s.cycle = "harjoitukset", "2026-09-29"
  t.eq(s:start(), 2)
  t.truthy(s:running())
  t.falsy(s:step(), "the first step must not finish everything")
  drive(s)
  t.falsy(s:running())
  t.eq(#s.results, 2)
  for _, r in ipairs(s.results) do t.truthy(r.ok); t.truthy(r.text:find("Vastaanotettu")) end
  t.truthy(fs.exists("/band/tuottaja/harjoitukset/2026-09-29/eka/eka.rpp"))
  s:refresh("/stage")
  t.eq(s.rows[1].status.kind, "already"); t.falsy(s.rows[1].selected)
  t.eq(#s.results, 2, "the confirmations must stay visible after the list is refreshed")
  s:scan("/stage")
  t.eq(#s.results, 0, "a fresh scan starts clean")
end)

t.test("a failing song is reported in plain words and does not stop the others", function()
  local fs = memfs.new()
  stage(fs, "/stage/a", "eka"); stage(fs, "/stage/b", "toka")
  local s = session.new(fs, band, "/band", S, "aino")
  s:scan("/stage")
  s.library, s.cycle = "harjoitukset", "2026-09-29"
  local real = fs.open_write
  fs.open_write = function(p) if p:find("eka.wav", 1, true) then return nil, "disk full" end return real(p) end
  s:start(); drive(s)
  t.eq(#s.results, 2)
  t.falsy(s.results[1].ok)
  t.truthy(s.results[1].text:find("eka: "))
  t.truthy(s.results[1].text:find("disk full"))
  t.truthy(s.results[2].ok)
end)

t.test("an invalid date is reported, not received", function()
  local fs = memfs.new()
  stage(fs, "/stage/a", "eka")
  local s = session.new(fs, band, "/band", S, "aino")
  s:scan("/stage")
  s.library, s.cycle = "harjoitukset", "not-a-date"
  s:start(); drive(s)
  t.falsy(s.results[1].ok)
  t.truthy(s.results[1].text:find("not%-a%-date"))
end)

t.test("a copy must be confirmed: skipping leaves it out, confirming receives it with a new id", function()
  local fs = memfs.new()
  stage(fs, "/stage/a", "eka")
  local s = session.new(fs, band, "/band", S, "aino")
  s:scan("/stage")
  s.library, s.cycle = "harjoitukset", "2026-09-29"
  s:start(); drive(s)
  local original = s.results[1].entry

  local to_copy = {}
  for path, data in pairs(fs.files) do
    if path:sub(1, #("/band/" .. original.path) + 1) == "/band/" .. original.path .. "/" then to_copy[#to_copy + 1] = { path, data } end
  end
  for _, f in ipairs(to_copy) do fs.files["/copyhere/x" .. f[1]:sub(#("/band/" .. original.path) + 1)] = f[2] end

  s:scan("/copyhere")
  local row = s.rows[1]
  t.eq(row.status.kind, "copy")
  t.falsy(s:can_select(row)); t.eq(#s:ready_rows(), 0)
  t.truthy(row.status.text:find(original.title, 1, true))

  s:decide(row, "skip")
  t.eq(#s:ready_rows(), 0)
  s:decide(row, "copy")
  t.truthy(s:can_select(row)); t.eq(#s:ready_rows(), 1)
  s.library = "levytys"
  s:start(); drive(s)
  t.truthy(s.results[1].ok)
  t.truthy(s.results[1].entry.id ~= original.id)
  t.eq(s.results[1].entry.origin.id, original.id)
end)

t.test("cycles can be listed and closed from the session, with plain messages on failure", function()
  local fs = memfs.new()
  stage(fs, "/stage/a", "eka")
  local s = session.new(fs, band, "/band", S, "aino")
  s:scan("/stage")
  s.library, s.cycle = "harjoitukset", "2026-09-29"
  s:start(); drive(s)
  t.eq(s:cycles_of("harjoitukset")[1].state, "open")
  t.eq(#s:cycles_of("levytys"), 0)
  t.truthy(s:close_cycle("harjoitukset", "2026-09-29"))
  t.eq(s:cycles_of("harjoitukset")[1].state, "closed")
  local ok, message = s:close_cycle("harjoitukset", "2030-01-01")
  t.eq(ok, nil)
  t.truthy(message:find("päivälle"))
end)

t.test("nothing found gives an empty list, and a damaged registry stops the session with a code", function()
  local s = session.new(memfs.new(), band, "/band", S, "aino")
  t.eq(s:scan("/empty"), 0)
  local bad, code = session.new(memfs.new({ ["/band/tuottaja/registry.json"] = "{oops" }), band, "/band", S, "aino")
  t.eq(bad, nil); t.eq(code, "registry_invalid")
end)
