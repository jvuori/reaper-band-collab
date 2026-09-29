local t = require("luatest")
local manifest = require("muuri.manifest")
local json = require("muuri.json")
local memfs = require("memfs")

local function pack()
  local fs = memfs.new({
    ["/p/media/take1.wav"] = ("a"):rep(5000),
    ["/p/media/take2.wav"] = ("b"):rep(300),
    ["/p/song.rpp"] = "<REAPER_PROJECT>",
  })
  local m = manifest.build(fs, "/p", { kind = "delivery", created = "2026-09-30T10:00:00Z" })
  t.truthy(manifest.write(fs, "/p", m))
  return fs, m
end

local function codes(problems)
  local out = {}
  for _, p in ipairs(problems) do out[#out + 1] = p.code .. ":" .. tostring(p.path) end
  table.sort(out)
  return table.concat(out, ",")
end

t.test("build lists files sorted with size and hash, excluding manifest and marker", function()
  local _, m = pack()
  t.eq(#m.files, 3)
  t.eq(m.files[1].path, "media/take1.wav")
  t.eq(m.files[2].path, "media/take2.wav")
  t.eq(m.files[3].path, "song.rpp")
  t.eq(m.files[1].size, 5000)
  t.eq(#m.files[1].hash, 16)
  t.eq(m.schema, 1)
  t.eq(m.kind, "delivery")
end)

t.test("an intact pack verifies", function()
  local fs = pack()
  local ok, problems = manifest.verify(fs, "/p")
  t.truthy(ok)
  t.eq(#problems, 0)
end)

t.test("the marker is written last and manifest is written before it", function()
  local order = {}
  local fs = memfs.new({ ["/p/a"] = "x" })
  local write = fs.write_all
  fs.write_all = function(path, data) order[#order + 1] = path; return write(path, data) end
  manifest.write(fs, "/p", manifest.build(fs, "/p"))
  t.eq(order[1], "/p/manifest.json")
  t.eq(order[#order], "/p/valmis")
end)

t.test("interrupted write (no marker) is refused", function()
  local fs = pack()
  fs.remove("/p/valmis")
  local ok, problems = manifest.verify(fs, "/p")
  t.falsy(ok)
  t.eq(codes(problems), "missing_marker:valmis")
end)

t.test("missing file is detected", function()
  local fs = pack()
  fs.remove("/p/media/take2.wav")
  local ok, problems = manifest.verify(fs, "/p")
  t.falsy(ok)
  t.eq(codes(problems), "missing_file:media/take2.wav")
end)

t.test("truncated file is a size mismatch and is not hashed", function()
  local fs = pack()
  fs.files["/p/media/take1.wav"] = ("a"):rep(4000)
  local ok, problems = manifest.verify(fs, "/p")
  t.falsy(ok)
  t.eq(codes(problems), "size_mismatch:media/take1.wav")
  t.eq(problems[1].expected, 5000)
  t.eq(problems[1].actual, 4000)
end)

t.test("same-size corruption is a hash mismatch, and can be skipped for speed", function()
  local fs = pack()
  fs.files["/p/media/take1.wav"] = ("a"):rep(2500) .. "Z" .. ("a"):rep(2499)
  local ok, problems = manifest.verify(fs, "/p")
  t.falsy(ok)
  t.eq(codes(problems), "hash_mismatch:media/take1.wav")
  local quick_ok = manifest.verify(fs, "/p", { check_hash = false })
  t.truthy(quick_ok)
end)

t.test("a replaced manifest no longer matches the marker", function()
  local fs = pack()
  local m = json.decode(fs.files["/p/manifest.json"])
  m.files[1].size = 1
  fs.files["/p/manifest.json"] = json.encode(m, { pretty = true }) .. "\n"
  local ok, problems = manifest.verify(fs, "/p")
  t.falsy(ok)
  t.eq(codes(problems), "marker_mismatch:valmis")
end)

t.test("garbage manifest is reported", function()
  local fs = pack()
  fs.files["/p/manifest.json"] = "not json"
  local ok, problems = manifest.verify(fs, "/p")
  t.falsy(ok)
  t.eq(codes(problems), "bad_manifest:manifest.json")
end)

t.test("several problems are all reported", function()
  local fs = pack()
  fs.remove("/p/song.rpp")
  fs.files["/p/media/take2.wav"] = "short"
  local _, problems = manifest.verify(fs, "/p")
  t.eq(codes(problems), "missing_file:song.rpp,size_mismatch:media/take2.wav")
end)

t.test("progress callback runs while building and verifying", function()
  local fs = pack()
  local calls = 0
  manifest.build(fs, "/p", { yield = function() calls = calls + 1 end })
  manifest.verify(fs, "/p", { yield = function() calls = calls + 1 end })
  t.truthy(calls >= 6)
end)

t.test("every problem code is documented in the list", function()
  local known = {}
  for _, c in ipairs(manifest.problems) do known[c] = true end
  for _, c in ipairs({ "missing_marker", "bad_manifest", "marker_mismatch", "missing_file", "size_mismatch", "hash_mismatch", "unreadable_file" }) do
    t.truthy(known[c], c)
  end
end)
