local t = require("luatest")
local fs = require("muuri.fs_std")
local manifest = require("muuri.manifest")

-- Listing needs REAPER's API or io.popen; some embedded Lua builds (like lupa's) disable popen.
local can_list = (reaper ~= nil) or pcall(io.popen, "true")
local function need_listing() if not can_list then t.skip("no directory listing in this runtime (run tests/reaper_runner.lua inside REAPER)") end end

local function tmpdir()
  local d = os.tmpname()
  os.remove(d)
  assert(fs.mkdirs(d .. "/media"))
  return d
end

t.test("write, read, size, exists, rename, remove on the real disk", function()
  local d = tmpdir()
  t.truthy(fs.write_all(d .. "/a.txt", "hello"))
  t.eq(fs.read_all(d .. "/a.txt"), "hello")
  t.eq(fs.size(d .. "/a.txt"), 5)
  t.truthy(fs.exists(d .. "/a.txt"))
  t.truthy(fs.rename(d .. "/a.txt", d .. "/b.txt"))
  t.falsy(fs.exists(d .. "/a.txt"))
  t.truthy(fs.remove(d .. "/b.txt"))
  t.eq(fs.size(d .. "/b.txt"), nil)
  local h, err = fs.open_read(d .. "/nope")
  t.eq(h, nil)
  t.truthy(err)
  os.execute("rm -rf '" .. d .. "'")
end)

t.test("list returns files and directories, including odd names", function()
  need_listing()
  local d = tmpdir()
  fs.write_all(d .. "/media/it's ä.wav", "x")
  local names = {}
  for _, e in ipairs(fs.list(d)) do names[e.name] = e.is_dir end
  t.eq(names.media, true)
  local sub = {}
  for _, e in ipairs(fs.list(d .. "/media")) do sub[e.name] = e.is_dir end
  t.eq(sub["it's ä.wav"], false)
  os.execute("rm -rf '" .. d .. "'")
end)

t.test("a real pack builds, verifies, and detects real corruption", function()
  need_listing()
  local d = tmpdir()
  fs.write_all(d .. "/media/take.wav", ("a"):rep(200000))
  fs.write_all(d .. "/song.rpp", "<REAPER_PROJECT>")
  local m = manifest.build(fs, d)
  t.truthy(manifest.write(fs, d, m))
  t.truthy(manifest.verify(fs, d))
  fs.write_all(d .. "/media/take.wav", ("a"):rep(100000) .. "Z" .. ("a"):rep(99999))
  local ok, problems = manifest.verify(fs, d)
  t.falsy(ok)
  t.eq(problems[1].code, "hash_mismatch")
  os.execute("rm -rf '" .. d .. "'")
end)
