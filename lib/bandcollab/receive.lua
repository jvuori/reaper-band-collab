-- Receiving a rehearsal: scan a staging folder, check each song arrived intact, work out what
-- each one is (new, moved, copy, already received), and move the chosen ones into the band
-- folder with an identity, a manifest and a registry entry.
local inspect = require("bandcollab.inspect")
local identity = require("bandcollab.identity")
local registry = require("bandcollab.registry")
local songfile = require("bandcollab.songfile")
local cycles = require("bandcollab.cycles")
local copytree = require("bandcollab.copytree")
local manifest = require("bandcollab.manifest")
local hash = require("bandcollab.hash")
local slug = require("bandcollab.slug")
local ids = require("bandcollab.ids")
local bandfile = require("bandcollab.bandfile")
local path = require("bandcollab.path")
local rpp = require("bandcollab.rpp")

local M = {}

-- Files that describe a song's identity and completeness are written fresh on receipt,
-- so stale copies from an earlier location are never carried over.
local GENERATED = { [songfile.FILENAME] = true, [manifest.MANIFEST] = true, [manifest.MARKER] = true }

-- context(fs, band, band_folder) -> ctx | nil, code  (loads the registry)
function M.context(fs, band, band_folder)
  local file = registry.file(band, band_folder)
  local reg, code = registry.load(fs, file)
  if not reg then return nil, code end
  return { fs = fs, band = band, band_folder = band_folder, registry = reg, registry_file = file }
end

-- candidates(ctx, staging [, opts]) -> list of songs found in the staging folder, each with:
--   rpp, dir, name, title (initial guess), inspection, identity, selected (true when it can be received)
function M.candidates(ctx, staging, opts)
  opts = opts or {}
  local out = {}
  for _, c in ipairs(inspect.scan(ctx.fs, staging)) do
    local text = ctx.fs.read_all(c.rpp) or ""
    c.title = rpp.title(text) or c.name -- a title set in the project beats the file name
    c.inspection = inspect.inspect(ctx.fs, c.rpp, { check_hash = opts.check_hash })
    c.source_hash = hash.string(text)
    c.identity = identity.classify(ctx.fs, ctx.band_folder, ctx.registry, c.dir, c.source_hash)
    if c.identity.state == "moved" then c.title = c.identity.entry.title end -- a moved song keeps its title
    c.selected = c.inspection.ok and (c.identity.state == "new" or c.identity.state == "moved")
    out[#out + 1] = c
  end
  return out
end

-- import(ctx, candidate, opts) -> entry | nil, code, detail
--   opts.library      library id (default: the first library of the band)
--   opts.cycle        YYYY-MM-DD for dated libraries (default: today)
--   opts.title        display title (default: the candidate's title)
--   opts.copy         true when the producer confirmed that a "copy" is a copy (a fresh id is assigned)
--   opts.yield, opts.now, opts.rng
-- Codes: incomplete, already_registered, already_received, copy_undecided, bad_date, unknown_library,
--        cannot_copy, cannot_write, cycle_closed
function M.import(ctx, cand, opts)
  opts = opts or {}
  local fs, band = ctx.fs, ctx.band
  local library
  if opts.library then library = bandfile.library(band, opts.library) else library = bandfile.libraries(band)[1] end
  if not library then return nil, "unknown_library", opts.library end
  local cycle = library.kind == "dated" and (opts.cycle or os.date("%Y-%m-%d")) or nil
  if cycle and not cycles.valid_date(cycle) then return nil, "bad_date", cycle end

  if not cand.inspection.ok then return nil, "incomplete", cand.inspection.problems end
  local id_info = cand.identity
  if id_info.state == "same" then return nil, "already_registered", id_info.entry.title end
  if id_info.state == "already_received" then return nil, "already_received", id_info.entry.title end
  if id_info.state == "copy" and not opts.copy then return nil, "copy_undecided", id_info.entry.title end

  -- identity: keep an unregistered or moved id; a confirmed copy gets a fresh one and remembers where it came from
  local origin
  local id = id_info.id
  if id_info.state == "copy" then
    origin = { id = id_info.id, path = id_info.entry.path, title = id_info.entry.title }
    id = nil
  end
  id = id or ids.generate(registry.taken(ctx.registry), opts.rng)

  local title = opts.title or cand.title
  local taken = {}
  local parent = cycles.song_dir(band, ctx.band_folder, library, cycle, "x"):gsub("/x$", "")
  for _, e in ipairs(fs.list(parent) or {}) do taken[e.name] = true end
  local name = slug.unique(slug.slug(title), taken)
  local dest = cycles.song_dir(band, ctx.band_folder, library, cycle, name)

  local ok, err = cycles.ensure(fs, band, ctx.band_folder, library, cycle, opts.now)
  if not ok then return nil, "cannot_write", err end
  if cycle then
    local open, code, detail = cycles.check_open(fs, band, ctx.band_folder, library.id, cycle)
    if not open then return nil, code, detail end -- a closed cycle is a frozen archive
  end

  local copied, cerr = copytree.copy(fs, cand.dir, dest, {
    skip = function(rel) return GENERATED[rel] end,
    yield = opts.yield,
  })
  if not copied then return nil, "cannot_copy", cerr end

  local created = opts.now or os.date("!%Y-%m-%dT%H:%M:%SZ")
  local rel = path.relative(ctx.band_folder, dest)
  local entry = {
    id = id, title = title, slug = name, library = library.id, cycle = cycle, path = rel,
    created = created, origin = origin, source_hash = cand.source_hash,
  }
  local wrote, werr = songfile.write(fs, dest, {
    id = id, title = title, slug = name, library = library.id, cycle = cycle, created = created, origin = origin,
  })
  if not wrote then return nil, "cannot_write", werr end
  local built = manifest.build(fs, dest, { kind = "song", created = created, meta = { song = id }, yield = opts.yield })
  local mok, merr = manifest.write(fs, dest, built)
  if not mok then return nil, "cannot_write", merr end

  -- the registry entry comes last: until now nothing points at a half-received song
  registry.put(ctx.registry, entry)
  local saved, serr = registry.save(fs, ctx.registry_file, ctx.registry)
  if not saved then return nil, "cannot_write", serr end
  return entry
end

return M
