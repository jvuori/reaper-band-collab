local t = require("luatest")
local hash = require("muuri.hash")
local memfs = require("memfs")

t.test("known answers stay stable (changing them breaks existing manifests)", function()
  t.eq(hash.string(""), "99481c74ebfdb67d")
  t.eq(hash.string("abc"), "276a698e6d7d5a9e")
  t.eq(hash.string(("0123456789"):rep(10)), "b30df9a244ecef79")
  t.eq(hash.string(("\0"):rep(64)), "6bc48e0544a7158a")
end)

t.test("different inputs give different hashes, including different lengths of zeros", function()
  local seen = {}
  for _, s in ipairs({ "", "a", "b", "ab", ("\0"):rep(1), ("\0"):rep(63), ("\0"):rep(64), ("\0"):rep(65), ("\0"):rep(128) }) do
    local h = hash.string(s)
    t.falsy(seen[h], "collision for input of length " .. #s)
    seen[h] = true
  end
end)

t.test("result does not depend on how the input is chunked", function()
  local data = {}
  for i = 1, 5000 do data[i] = string.char((i * 31 + i // 7) % 256) end
  local s = table.concat(data)
  local whole = hash.string(s)
  for _, size in ipairs({ 1, 7, 63, 64, 65, 100, 4999 }) do
    local hs = hash.new()
    for i = 1, #s, size do hs:feed(s:sub(i, i + size - 1)) end
    t.eq(hs:finish(), whole, "chunk size " .. size)
  end
end)

t.test("a single changed byte changes the hash", function()
  local s = ("x"):rep(1000)
  t.truthy(hash.string(s) ~= hash.string(s:sub(1, 499) .. "y" .. s:sub(501)))
end)

t.test("file hashing matches string hashing and reports progress", function()
  local s = ("0123456789"):rep(100000) -- 1 MB
  local fs = memfs.new({ ["/x/a.wav"] = s })
  local ticks = 0
  local old = hash.SLICE
  hash.SLICE = 256 * 1024
  local h, size = hash.file(fs, "/x/a.wav", function() ticks = ticks + 1 end)
  hash.SLICE = old
  t.eq(h, hash.string(s))
  t.eq(size, #s)
  t.eq(ticks, 4)
end)

t.test("unreadable file returns nil and a message", function()
  local h, err = hash.file(memfs.new({}), "/missing")
  t.eq(h, nil)
  t.truthy(err:find("missing"))
end)
