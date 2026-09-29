-- hash64-v1: fast non-cryptographic 64-bit hash for detecting truncated or corrupt files
-- (see docs/spikes/checksum.md). The result does not depend on how the input is split
-- into chunks. It does NOT protect against forgery.
local M = {}

M.ALGORITHM = "hash64-v1"
M.SLICE = 16 * 1024 * 1024 -- bytes hashed between yields; must be a multiple of 64

local unpack = string.unpack
local P1 = 0x9E3779B185EBCA87
local P2 = 0xC2B2AE3D27D4EB4F
local SEED = 0x1234567

local function blocks(h, s, first, last)
  local p = first
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
  return h
end

local Hasher = {}
Hasher.__index = Hasher

function M.new() return setmetatable({ h = SEED, buf = "", len = 0 }, Hasher) end

function Hasher:feed(s)
  self.len = self.len + #s
  local data = self.buf .. s
  local usable = #data - (#data % 64)
  if usable > 0 then self.h = blocks(self.h, data, 1, usable - 63) end
  self.buf = data:sub(usable + 1)
  return self
end

-- Returns the final hash as 16 lowercase hex digits. The hasher must not be fed afterwards.
function Hasher:finish()
  local h = self.h
  for i = 1, #self.buf do
    h = (h ~ self.buf:byte(i)) * P1; h = h ~ (h >> 29)
  end
  h = (h ~ self.len) * P2; h = h ~ (h >> 31)
  h = (h ~ (h >> 33)) * P1
  return string.format("%016x", h)
end

function M.string(s) return M.new():feed(s):finish() end

-- hash.file(fs, path [, yield]) -> hex, size  |  nil, error
-- Reads in slices of M.SLICE bytes; after each slice calls yield(bytes_done) if given, so a
-- caller running inside a coroutine can hand control back to REAPER and show progress.
function M.file(fs, path, yield)
  local fh, err = fs.open_read(path)
  if not fh then return nil, err end
  local hasher, done = M.new(), 0
  while true do
    local chunk = fh:read(M.SLICE)
    if not chunk or #chunk == 0 then break end
    hasher:feed(chunk)
    done = done + #chunk
    if yield then yield(done) end
  end
  fh:close()
  return hasher:finish(), done
end

return M
