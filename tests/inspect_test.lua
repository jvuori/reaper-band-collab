local t = require("luatest")
local inspect = require("bandcollab.inspect")
local manifest = require("bandcollab.manifest")
local memfs = require("memfs")

local function wav(n)
  local body = "WAVE" .. "fmt " .. string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, 48000, 96000, 2, 16) .. "data" .. string.pack("<I4", n) .. ("\1"):rep(n)
  return "RIFF" .. string.pack("<I4", #body) .. body
end

local function project(files)
  local text = "<REAPER_PROJECT 0.1 \"7.0\" 0\n"
  for _, f in ipairs(files) do text = text .. "  <ITEM\n    <SOURCE WAVE\n      FILE \"" .. f .. "\"\n    >\n  >\n" end
  return text .. ">\n"
end

local function codes(result)
  local out = {}
  for _, p in ipairs(result.problems) do out[#out + 1] = p.code .. ":" .. p.path end
  table.sort(out)
  return table.concat(out, ",")
end

t.test("three projects with arbitrary folder names are all found, and nothing else", function()
  local fs = memfs.new({
    ["/stage/ilta1/eka biisi.rpp"] = project({}),
    ["/stage/xyz/foo.RPP"] = project({}),
    ["/stage/xyz/deeper/Yö.rpp"] = project({}),
    ["/stage/xyz/foo.rpp-bak"] = "backup",
    ["/stage/xyz/notes.txt"] = "hi",
    ["/stage/.hidden/secret.rpp"] = project({}),
    ["/stage/xyz/media/a.wav"] = "x",
  })
  local found = inspect.scan(fs, "/stage")
  t.eq(#found, 3)
  local names = {}
  for _, f in ipairs(found) do names[#names + 1] = f.name end
  t.eq(table.concat(names, "|"), "eka biisi|Yö|foo")
  t.eq(found[1].dir, "/stage/ilta1")
end)

t.test("a complete project has no problems", function()
  local fs = memfs.new({
    ["/p/song.rpp"] = project({ "media/a.wav", "media/b.wav" }),
    ["/p/media/a.wav"] = wav(500), ["/p/media/b.wav"] = wav(800),
  })
  local r = inspect.inspect(fs, "/p/song.rpp")
  t.truthy(r.ok)
  t.eq(r.media, 2)
  t.eq(#r.problems, 0)
  t.falsy(r.has_manifest)
end)

t.test("a missing media file is reported by name", function()
  local fs = memfs.new({ ["/p/song.rpp"] = project({ "media/a.wav", "media/b.wav" }), ["/p/media/a.wav"] = wav(500) })
  local r = inspect.inspect(fs, "/p/song.rpp")
  t.falsy(r.ok)
  t.eq(codes(r), "missing_file:media/b.wav")
end)

t.test("a truncated media file is reported (interrupted copy)", function()
  local full = wav(4000)
  local fs = memfs.new({ ["/p/song.rpp"] = project({ "media/a.wav" }), ["/p/media/a.wav"] = full:sub(1, 2000) })
  t.eq(codes(inspect.inspect(fs, "/p/song.rpp")), "truncated_file:media/a.wav")
end)

t.test("an empty media file is reported", function()
  local fs = memfs.new({ ["/p/song.rpp"] = project({ "media/a.wav" }), ["/p/media/a.wav"] = "" })
  t.eq(codes(inspect.inspect(fs, "/p/song.rpp")), "empty_file:media/a.wav")
end)

t.test("media stored with Windows separators and absolute paths from another computer", function()
  local fs = memfs.new({
    ["/p/song.rpp"] = project({ "media\\a.wav", "/home/laptop/rec/b.wav" }),
    ["/p/media/a.wav"] = wav(100),
  })
  local r = inspect.inspect(fs, "/p/song.rpp")
  t.eq(codes(r), "missing_file:/home/laptop/rec/b.wav")
end)

t.test("a project that cannot be read is reported", function()
  local r = inspect.inspect(memfs.new(), "/p/song.rpp")
  t.falsy(r.ok)
  t.eq(codes(r), "missing_file:song.rpp")
end)

t.test("when a finished manifest is present it is verified too, and duplicates are not repeated", function()
  local fs = memfs.new({
    ["/p/song.rpp"] = project({ "media/a.wav" }),
    ["/p/media/a.wav"] = wav(500),
  })
  local m = manifest.build(fs, "/p")
  manifest.write(fs, "/p", m)
  local ok = inspect.inspect(fs, "/p/song.rpp")
  t.truthy(ok.ok); t.truthy(ok.has_manifest)

  -- corrupt the media without changing its size: only the manifest can tell
  local damaged = wav(500):sub(1, -2) .. "\2"
  fs.files["/p/media/a.wav"] = damaged
  t.eq(codes(inspect.inspect(fs, "/p/song.rpp")), "hash_mismatch:media/a.wav")
  t.truthy(inspect.inspect(fs, "/p/song.rpp", { check_hash = false }).ok)

  -- a truncated file is reported once, not once by the WAV check and again by the manifest
  fs.files["/p/media/a.wav"] = wav(500):sub(1, 300)
  t.eq(codes(inspect.inspect(fs, "/p/song.rpp")), "truncated_file:media/a.wav")
end)

t.test("every code inspect can produce has a message in both languages", function()
  local strings = require("bandcollab.strings")
  local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")
  for _, c in ipairs({ "missing_file", "empty_file", "truncated_file", "size_mismatch", "hash_mismatch", "missing_marker", "bad_manifest", "marker_mismatch", "unreadable_file" }) do
    t.truthy(S:has("err." .. c .. ".what", "en") and S:has("err." .. c .. ".what", "fi"), c)
  end
end)
