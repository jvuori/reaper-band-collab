local t = require("luatest")
local revisions = require("bandcollab.revisions")
local manifest = require("bandcollab.manifest")
local memfs = require("memfs")

local PUB = "/band/publications/rehearsals/2026-09-29/song"

-- writes a finished revision the way the publisher does: files, then manifest, then marker last
local function publish(fs, number, files)
  local dir = revisions.dir(PUB, number)
  assert(revisions.writable(fs, dir))
  for name, data in pairs(files) do fs.files[dir .. "/" .. name] = data end
  assert(manifest.write(fs, dir, manifest.build(fs, dir, { created = "T" })))
  return dir
end

local function snapshot(fs, dir)
  local out = {}
  for path, data in pairs(fs.files) do if path:sub(1, #dir + 1) == dir .. "/" then out[path] = data end end
  return out
end

local function equal(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end

t.test("the first publish is r1", function()
  local fs = memfs.new()
  local n, dir, removed = revisions.next(fs, PUB)
  t.eq(n, 1); t.eq(dir, PUB .. "/r1"); t.eq(removed, 0)
end)

t.test("a second publish makes r2 and leaves r1 byte for byte unchanged", function()
  local fs = memfs.new()
  local r1 = publish(fs, 1, { ["stems/bass.wav"] = "BASS-1", ["reference.wav"] = "MIX-1", ["timing.json"] = '{"length":180}' })
  local before = snapshot(fs, r1)
  local n = revisions.next(fs, PUB)
  t.eq(n, 2)
  publish(fs, 2, { ["stems/bass.wav"] = "BASS-2", ["reference.wav"] = "MIX-2", ["timing.json"] = '{"length":184}' })
  t.truthy(equal(before, snapshot(fs, r1)), "r1 changed")
  t.eq(revisions.next(fs, PUB), 3)
  t.eq(revisions.latest(fs, PUB).number, 2)
  t.truthy(manifest.verify(fs, r1))
end)

t.test("writing into a completed revision is refused", function()
  local fs = memfs.new()
  local r1 = publish(fs, 1, { ["a.wav"] = "x" })
  local ok, code = revisions.writable(fs, r1)
  t.eq(ok, nil); t.eq(code, "revision_complete")
  t.truthy(revisions.writable(fs, PUB .. "/r2"))
end)

t.test("a leftover of an interrupted publish is emptied and its number reused", function()
  local fs = memfs.new()
  publish(fs, 1, { ["a.wav"] = "x" })
  fs.files[PUB .. "/r2/stems/bass.wav"] = "half a stem"
  fs.files[PUB .. "/r2/manifest.json"] = "{}"          -- no marker: the publish never finished
  local n, dir, removed = revisions.next(fs, PUB)
  t.eq(n, 2); t.eq(dir, PUB .. "/r2"); t.eq(removed, 2)
  t.falsy(fs.exists(PUB .. "/r2/stems/bass.wav"))
  t.eq(revisions.latest(fs, PUB).number, 1, "an incomplete revision must never count as the latest")
end)

t.test("only real revision folders count", function()
  local fs = memfs.new({
    [PUB .. "/notes/x.txt"] = "n", [PUB .. "/r/x"] = "n", [PUB .. "/rx1/x"] = "n", [PUB .. "/r01/x"] = "n", [PUB .. "/r1.zip"] = "n",
  })
  t.eq(#revisions.list(fs, PUB), 0)
  t.eq(revisions.next(fs, PUB), 1)
  publish(fs, 7, { ["a"] = "x" })
  t.eq(revisions.next(fs, PUB), 8)
end)

t.test("consumers refuse a publication that was interrupted mid-write, at every point", function()
  -- a complete publication has files, manifest, marker; cut the write off after each step
  local files = { ["stems/bass.wav"] = ("b"):rep(3000), ["reference.wav"] = ("m"):rep(2000), ["timing.json"] = "{}" }
  local full = memfs.new()
  local dir = publish(full, 1, files)
  local order = { "stems/bass.wav", "reference.wav", "timing.json", "manifest.json", "valmis" }
  for cut = 1, #order - 1 do
    local fs = memfs.new()
    for i = 1, cut do fs.files[dir .. "/" .. order[i]] = full.files[dir .. "/" .. order[i]] end
    local ok, problems = manifest.verify(fs, dir)
    t.falsy(ok, "accepted a publication cut after " .. order[cut])
    t.eq(problems[1].code, "missing_marker")
  end
  t.truthy(manifest.verify(full, dir))
  -- a file only partly synced: the marker is there but a stem is short
  local partial = memfs.new()
  for k, v in pairs(full.files) do partial.files[k] = v end
  partial.files[dir .. "/stems/bass.wav"] = ("b"):rep(1500)
  local ok, problems = manifest.verify(partial, dir)
  t.falsy(ok); t.eq(problems[1].code, "size_mismatch")
  t.eq(#revisions.list(partial, PUB), 1)
end)
