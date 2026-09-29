-- Manifests prove that a pack (publication, delivery, received rehearsal) is complete and intact.
-- A pack directory holds its files, a manifest.json listing each one with size and hash, and a
-- `valmis` marker that is written LAST. A consumer that finds no marker, or a marker that does
-- not match, or files that differ from the manifest, must refuse the pack.
local json = require("bandcollab.json")
local hash = require("bandcollab.hash")

local M = {}

M.SCHEMA = 1
M.MANIFEST = "manifest.json"
M.MARKER = "valmis"

-- Problem codes returned by verify (each has a matching err.* message in strings/).
M.problems = {
  "missing_marker", "bad_manifest", "marker_mismatch", "missing_file", "size_mismatch",
  "hash_mismatch", "unreadable_file",
}

local function scan(fs, root, rel, out)
  local dir = rel == "" and root or (root .. "/" .. rel)
  for _, e in ipairs(fs.list(dir) or {}) do
    local r = rel == "" and e.name or (rel .. "/" .. e.name)
    if e.is_dir then scan(fs, root, r, out)
    elseif r ~= M.MANIFEST and r ~= M.MARKER then out[#out + 1] = r end
  end
end

-- build(fs, root [, opts]) -> manifest table
--   opts.kind, opts.meta      free-form descriptors stored in the manifest
--   opts.created              timestamp string (default: now, UTC ISO 8601)
--   opts.yield(done, path)    called after each hashed slice (for UI progress)
function M.build(fs, root, opts)
  opts = opts or {}
  local paths = {}
  scan(fs, root, "", paths)
  table.sort(paths)
  local files = json.array()
  for _, rel in ipairs(paths) do
    local digest, size = hash.file(fs, root .. "/" .. rel, opts.yield and function(done) opts.yield(done, rel) end)
    if not digest then error("cannot read " .. rel .. ": " .. tostring(size), 0) end
    files[#files + 1] = { path = rel, size = size, hash = digest }
  end
  return {
    schema = M.SCHEMA,
    algorithm = hash.ALGORITHM,
    kind = opts.kind,
    meta = opts.meta,
    created = opts.created or os.date("!%Y-%m-%dT%H:%M:%SZ"),
    files = files,
  }
end

-- write(fs, root, manifest): writes manifest.json, then the completion marker last.
function M.write(fs, root, manifest)
  local text = json.encode(manifest, { pretty = true }) .. "\n"
  local ok, err = fs.write_all(root .. "/" .. M.MANIFEST, text)
  if not ok then return nil, err end
  local marker = json.encode({ schema = M.SCHEMA, manifest_hash = hash.string(text) })
  return fs.write_all(root .. "/" .. M.MARKER, marker .. "\n")
end

-- verify(fs, root [, opts]) -> ok, problems
--   opts.check_hash = false skips hashing (sizes are always checked)
--   opts.yield(done, path) for progress while hashing
-- problems is a list of { code =, path =, expected =, actual = }.
function M.verify(fs, root, opts)
  opts = opts or {}
  local problems = {}
  local function add(code, path, expected, actual)
    problems[#problems + 1] = { code = code, path = path, expected = expected, actual = actual }
  end

  local marker_text = fs.read_all(root .. "/" .. M.MARKER)
  if not marker_text then add("missing_marker", M.MARKER); return false, problems end

  local manifest_text = fs.read_all(root .. "/" .. M.MANIFEST)
  local manifest = manifest_text and json.try_decode(manifest_text)
  if type(manifest) ~= "table" or type(manifest.files) ~= "table" or manifest.schema ~= M.SCHEMA then
    add("bad_manifest", M.MANIFEST); return false, problems
  end

  local marker = json.try_decode(marker_text)
  if type(marker) ~= "table" or marker.manifest_hash ~= hash.string(manifest_text) then
    add("marker_mismatch", M.MARKER); return false, problems
  end

  for _, f in ipairs(manifest.files) do
    local path = root .. "/" .. f.path
    local size = fs.size(path)
    if size == nil then
      add("missing_file", f.path)
    elseif size ~= f.size then
      add("size_mismatch", f.path, f.size, size)
    elseif opts.check_hash ~= false then
      local digest, err = hash.file(fs, path, opts.yield and function(done) opts.yield(done, f.path) end)
      if not digest then add("unreadable_file", f.path, nil, err)
      elseif digest ~= f.hash then add("hash_mismatch", f.path, f.hash, digest) end
    end
  end
  return #problems == 0, problems
end

return M
