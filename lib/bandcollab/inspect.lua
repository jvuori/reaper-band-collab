-- Inspects a project that has arrived (for example over SCP): did everything it needs arrive intact?
-- Works on the media files the project names, so it needs no manifest; if a finished manifest is
-- present next to the project, that is verified as well.
local rpp = require("bandcollab.rpp")
local wavcheck = require("bandcollab.wavcheck")
local manifest = require("bandcollab.manifest")
local path = require("bandcollab.path")

local M = {}

-- Problem codes (each has an err.<code> message in strings/):
--   missing_file, empty_file, truncated_file, and the manifest codes (size_mismatch, hash_mismatch, ...)

-- resolve(project_dir, ref) -> full path of a media file named in the project
function M.resolve(project_dir, ref)
  ref = ref:gsub("\\", "/")
  if rpp.is_absolute(ref) then return ref end
  return project_dir .. "/" .. ref
end

-- inspect(fs, rpp_file [, opts]) -> { ok =, media = n, problems = { {code=, path=}... }, has_manifest = bool }
--   opts.check_hash = false skips hashing when a manifest is present
function M.inspect(fs, rpp_file, opts)
  opts = opts or {}
  local dir = path.dirname(rpp_file)
  local text, err = fs.read_all(rpp_file)
  local result = { ok = true, media = 0, problems = {}, has_manifest = false }
  local function add(code, p, extra)
    result.ok = false
    local rec = { code = code, path = p }
    for k, v in pairs(extra or {}) do rec[k] = v end
    result.problems[#result.problems + 1] = rec
  end
  if not text then add("missing_file", path.basename(rpp_file)); return result end

  for _, ref in ipairs(rpp.media_refs(text)) do
    result.media = result.media + 1
    local full = M.resolve(dir, ref)
    local size = fs.size(full)
    if size == nil then
      add("missing_file", ref)
    else
      local verdict = wavcheck.check(fs, full)
      if verdict == "empty" then add("empty_file", ref)
      elseif verdict == "truncated" then add("truncated_file", ref) end
    end
  end

  if fs.exists(dir .. "/" .. manifest.MARKER) or fs.exists(dir .. "/" .. manifest.MANIFEST) then
    result.has_manifest = true
    local ok, problems = manifest.verify(fs, dir, { check_hash = opts.check_hash })
    if not ok then
      for _, p in ipairs(problems) do
        -- a media file already reported above must not be reported twice
        local dup = false
        for _, q in ipairs(result.problems) do if q.path == p.path and (q.code == p.code or p.code == "size_mismatch") then dup = true end end
        if not dup then add(p.code, p.path, { expected = p.expected, actual = p.actual }) end
      end
    end
  end
  return result
end

-- scan(fs, staging) -> list of { rpp =, dir =, name = } for every project file below `staging`.
-- Every project file is a song; nothing about folder names is assumed.
function M.scan(fs, staging)
  local out = {}
  local function walk(dir)
    for _, e in ipairs(fs.list(dir) or {}) do
      if e.is_dir then
        if e.name:sub(1, 1) ~= "." then walk(dir .. "/" .. e.name) end
      elseif e.name:lower():match("%.rpp$") then
        out[#out + 1] = { rpp = dir .. "/" .. e.name, dir = dir, name = e.name:gsub("%.[rR][pP][pP]$", "") }
      end
    end
  end
  walk(staging)
  table.sort(out, function(a, b) return a.rpp < b.rpp end)
  return out
end

return M
