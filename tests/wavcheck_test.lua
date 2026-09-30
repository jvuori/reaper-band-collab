local t = require("luatest")
local wavcheck = require("bandcollab.wavcheck")
local memfs = require("memfs")

-- A minimal PCM WAV: header, optional extra chunk before data, and n bytes of audio.
local function wav(n, opts)
  opts = opts or {}
  local extra = opts.list and ("LIST" .. string.pack("<I4", 5) .. "abcde\0") or ""
  local data = ("\1"):rep(n)
  local declared = opts.declared or n
  local body = "WAVE" .. "fmt " .. string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, 48000, 96000, 2, 16) .. extra
    .. "data" .. string.pack("<I4", declared) .. data
  return "RIFF" .. string.pack("<I4", #body) .. body
end

local function fsw(files) return memfs.new(files) end

t.test("a complete WAV is ok", function()
  t.eq(wavcheck.check(fsw({ ["/a.wav"] = wav(1000) }), "/a.wav"), "ok")
end)

t.test("a WAV cut short is truncated, however much is missing", function()
  local full = wav(1000)
  for _, cut in ipairs({ 1, 10, 500, 999 }) do
    t.eq(wavcheck.check(fsw({ ["/a.wav"] = full:sub(1, #full - cut) }), "/a.wav"), "truncated", "cut " .. cut)
  end
end)

t.test("an empty file is empty", function()
  t.eq(wavcheck.check(fsw({ ["/a.wav"] = "" }), "/a.wav"), "empty")
  t.eq(wavcheck.check(fsw({ ["/a.flac"] = "" }), "/a.flac"), "empty")
end)

t.test("extra chunks before the data chunk are skipped", function()
  local full = wav(2000, { list = true })
  t.eq(wavcheck.check(fsw({ ["/a.wav"] = full }), "/a.wav"), "ok")
  t.eq(wavcheck.check(fsw({ ["/a.wav"] = full:sub(1, #full - 5) }), "/a.wav"), "truncated")
end)

t.test("an unfinished header (size 0 or 0xFFFFFFFF) is not called truncated", function()
  t.eq(wavcheck.check(fsw({ ["/a.wav"] = wav(500, { declared = 0 }) }), "/a.wav"), "unknown")
  t.eq(wavcheck.check(fsw({ ["/a.wav"] = wav(500, { declared = 0xFFFFFFFF }) }), "/a.wav"), "unknown")
end)

t.test("files we cannot judge are unknown, and a missing file is unknown", function()
  t.eq(wavcheck.check(fsw({ ["/a.flac"] = "fLaC data" }), "/a.flac"), "unknown")
  t.eq(wavcheck.check(fsw({ ["/a.wav"] = "not a riff file at all" }), "/a.wav"), "unknown")
  t.eq(wavcheck.check(fsw({}), "/missing.wav"), "unknown")
end)
