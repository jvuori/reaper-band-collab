-- Benchmarks pure-Lua checksums on a big file. Works in REAPER and in plain Lua 5.4.
-- Env: BENCH_FILE (required), BENCH_OUT (optional output file; REAPER quits when done).
local path = assert(os.getenv("BENCH_FILE"), "BENCH_FILE not set")
local outpath = os.getenv("BENCH_OUT")
local lines = {}
local function w(...) lines[#lines + 1] = string.format(...) ; if not outpath then print(lines[#lines]) end end

local unpack = string.unpack
local CHUNK = 1 << 20 -- 1 MiB

-- Fast 64-bit hash (multiply-xorshift over 8-byte words). Not cryptographic:
-- it detects truncation and corruption from interrupted sync, not tampering.
local P1 = 0x9E3779B185EBCA87
local P2 = 0xC2B2AE3D27D4EB4F
local function hash64_chunk(h, s)
  local n = #s
  local p = 1
  local last = n - (n % 64)
  while p <= last do
    local a, b, c, d, e, f, g, hh = unpack("<i8i8i8i8i8i8i8i8", s, p)
    h = (h ~ a) * P1; h = h ~ (h >> 29)
    h = (h ~ b) * P2; h = h ~ (h >> 31)
    h = (h ~ c) * P1; h = h ~ (h >> 29)
    h = (h ~ d) * P2; h = h ~ (h >> 31)
    h = (h ~ e) * P1; h = h ~ (h >> 29)
    h = (h ~ f) * P2; h = h ~ (h >> 31)
    h = (h ~ g) * P1; h = h ~ (h >> 29)
    h = (h ~ hh) * P2; h = h ~ (h >> 31)
    p = p + 64
  end
  while p <= n do -- tail bytes
    h = (h ~ s:byte(p)) * P1; h = h ~ (h >> 29)
    p = p + 1
  end
  return h
end

-- CRC-32 (byte table), for comparison.
local crctab = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do c = (c & 1 == 1) and (0xEDB88320 ~ (c >> 1)) or (c >> 1) end
  crctab[i] = c
end
local function crc32_chunk(crc, s)
  for i = 1, #s do crc = crctab[(crc ~ s:byte(i)) & 0xFF] ~ (crc >> 8) end
  return crc
end

local function bench(name, limit_bytes, fn, init)
  local f = assert(io.open(path, "rb"))
  local size = f:seek("end"); f:seek("set", 0)
  local total, acc = 0, init
  local t0 = os.clock()
  while total < limit_bytes do
    local s = f:read(CHUNK)
    if not s then break end
    acc = fn(acc, s)
    total = total + #s
  end
  local dt = os.clock() - t0
  f:close()
  w("%-28s %8.1f MB in %6.2f s = %7.1f MB/s   result=%x  (file %d MB)", name, total / 1e6, dt, total / 1e6 / dt, acc & 0xFFFFFFFFFFFFFFFF, size // 1000000)
  return total / 1e6 / dt
end

w("Lua: %s", _VERSION)
local f = assert(io.open(path, "rb")); local size = f:seek("end"); f:close()
bench("hash64 full file", size, hash64_chunk, 0x1234567)
bench("crc32 first 32 MB", 32 * 1000 * 1000, crc32_chunk, 0xFFFFFFFF)

-- Correctness: same content, different chunking, gives the same hash only if chunk sizes
-- are multiples of 64 (we always use 1 MiB), and a one-byte change changes the hash.
local f2 = assert(io.open(path, "rb")); local s = f2:read(4 * CHUNK); f2:close()
local h1 = hash64_chunk(0x1234567, s)
local s2 = s:sub(1, 1000) .. string.char((s:byte(1001) ~ 1) & 0xFF) .. s:sub(1002)
local h2 = hash64_chunk(0x1234567, s2)
w("one-byte change detected: %s", tostring(h1 ~= h2))

if outpath then
  local o = io.open(outpath, "w"); o:write(table.concat(lines, "\n"), "\n"); o:close()
  if reaper then reaper.Main_OnCommand(40004, 0) end
end
