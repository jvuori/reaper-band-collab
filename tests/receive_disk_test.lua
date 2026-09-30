-- Receiving a rehearsal on a real disk with real files (needs REAPER for directory listing;
-- run through tests/reaper_runner.lua). The transfer from the recording computer is simulated:
-- files are written directly, one of them cut short, exactly what an interrupted copy leaves behind.
local t = require("luatest")
local function need_reaper() if not reaper then t.skip("needs REAPER (tests/reaper_runner.lua)") end end

local function wav_bytes(n)
  local body = "WAVE" .. "fmt " .. string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, 48000, 96000, 2, 16) .. "data" .. string.pack("<I4", n)
  local chunk = ("0123456789abcdef"):rep(4096) -- 64 KiB
  local parts, left = {}, n
  while left > 0 do local take = math.min(left, #chunk); parts[#parts + 1] = chunk:sub(1, take); left = left - take end
  body = body .. table.concat(parts)
  return "RIFF" .. string.pack("<I4", #body) .. body
end

local function write(path, data) local f = assert(io.open(path, "wb")); f:write(data); f:close() end

local function song(fs, dir, name, size)
  fs.mkdirs(dir .. "/media")
  write(dir .. "/" .. name .. ".rpp", "<REAPER_PROJECT 0.1 \"7.0\" 0\n  <ITEM\n    <SOURCE WAVE\n      FILE \"media/" .. name .. ".wav\"\n    >\n  >\n>\n")
  write(dir .. "/media/" .. name .. ".wav", wav_bytes(size))
end

t.test("a rehearsal arrives on disk: complete songs are received, a cut-short one is refused until it is copied again", function()
  need_reaper()
  local fs = require("bandcollab.fs_std")
  local bandfile = require("bandcollab.bandfile")
  local receive = require("bandcollab.receive")
  local registry = require("bandcollab.registry")
  local manifest = require("bandcollab.manifest")
  local cycles = require("bandcollab.cycles")
  local copytree = require("bandcollab.copytree")

  local root = os.tmpname(); os.remove(root)
  local band = {
    schema = 1, name = "Example Band", language = "en", producer = "aino",
    roles = { { id = "bass", label = "Bass" } }, members = { { id = "aino", name = "Aino", roles = { "bass" } } },
    locations = { master = "producer", publications = "publications", proposals = "proposals" },
  }
  for _, d in ipairs({ "producer", "publications", "proposals" }) do fs.mkdirs(root .. "/band/" .. d) end
  t.truthy(bandfile.write(fs, root .. "/band", band))

  song(fs, root .. "/stage/evening/one", "first", 2 * 1024 * 1024 + 123)
  song(fs, root .. "/stage/evening/two", "second", 700 * 1024)
  song(fs, root .. "/stage/three", "third", 900 * 1024)
  -- the third song's copy was interrupted: its recording is cut short
  local full = wav_bytes(900 * 1024)
  write(root .. "/stage/three/media/third.wav", full:sub(1, 300 * 1024))

  local ctx = assert(receive.context(fs, band, root .. "/band"))
  local list = receive.candidates(ctx, root .. "/stage")
  t.eq(#list, 3)
  local by = {}
  for _, c in ipairs(list) do by[c.name] = c end
  t.truthy(by.first.selected); t.truthy(by.second.selected)
  t.falsy(by.third.selected)
  t.eq(by.third.inspection.problems[1].code, "truncated_file")

  local saved_chunk, ticks = copytree.CHUNK, 0
  copytree.CHUNK = 64 * 1024
  for _, name in ipairs({ "first", "second" }) do
    local entry, code = receive.import(ctx, by[name], { cycle = "2026-09-29", now = "T", yield = function() ticks = ticks + 1 end })
    t.truthy(entry, code)
    t.eq(entry.path, "producer/rehearsals/2026-09-29/" .. name)
    t.truthy(manifest.verify(fs, root .. "/band/" .. entry.path))
    t.eq(fs.size(root .. "/band/" .. entry.path .. "/media/" .. name .. ".wav"), fs.size(root .. "/stage/" .. (name == "first" and "evening/one" or "evening/two") .. "/media/" .. name .. ".wav"))
  end
  copytree.CHUNK = saved_chunk
  t.truthy(ticks > 30, "large files must be copied in several chunks, saw " .. ticks)

  local refused, code = receive.import(ctx, by.third, { cycle = "2026-09-29", now = "T" })
  t.eq(refused, nil); t.eq(code, "incomplete")

  -- the registry on disk knows exactly the two received songs
  local reloaded = registry.load(fs, registry.file(band, root .. "/band"))
  t.eq(#registry.list(reloaded), 2)
  t.falsy(fs.exists(registry.file(band, root .. "/band") .. ".tmp"))
  t.eq(cycles.list(fs, band, root .. "/band", bandfile.libraries(band)[1])[1].cycle, "2026-09-29")
  t.truthy(fs.exists(root .. "/band/publications/rehearsals/2026-09-29/cycle.json"))

  -- the song is copied again and now arrives whole
  write(root .. "/stage/three/media/third.wav", full)
  local again = receive.candidates(ctx, root .. "/stage")
  local third
  for _, c in ipairs(again) do if c.name == "third" then third = c end end
  t.truthy(third.selected)
  t.truthy(receive.import(ctx, third, { cycle = "2026-09-29", now = "T" }))

  -- receiving the same folder once more registers nothing new
  local states = {}
  for _, c in ipairs(receive.candidates(ctx, root .. "/stage")) do states[#states + 1] = c.identity.state end
  t.eq(table.concat(states, ","), "already_received,already_received,already_received")
  t.eq(#registry.list(ctx.registry), 3)

  os.execute("rm -rf '" .. root .. "'")
end)
