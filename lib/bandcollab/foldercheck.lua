-- "Tarkista kansiot": looks over the band folder and REPORTS what is out of order. It never
-- changes anything by itself; fixes exist only for leftovers nothing needs, and only run when asked.
local registry = require("bandcollab.registry")
local revisions = require("bandcollab.revisions")
local deliveries = require("bandcollab.deliveries")
local manifest = require("bandcollab.manifest")
local cycles = require("bandcollab.cycles")
local bandfile = require("bandcollab.bandfile")
local songfile = require("bandcollab.songfile")
local inspect = require("bandcollab.inspect")
local rpp = require("bandcollab.rpp")
local slug = require("bandcollab.slug")
local path = require("bandcollab.path")
local wm = require("bandcollab.workspace_model")

local M = {}

-- Files tool writes into the structure on purpose; they are never reported as bad names.
local KNOWN_FILES = {
  ["registry.json"] = true, ["cycle.json"] = true, ["imports.json"] = true, ["guardian.log"] = true,
  ["band.json"] = true, ["song.json"] = true, ["manifest.json"] = true, ["valmis"] = true, ["workspace.json"] = true,
  ["CHANGELOG.md"] = true, ["MUUTOSLOKI.md"] = true,
}

local function entries(fs, dir) return fs.list(dir) or {} end

-- Folders that hold copies, not songs: the tool's own backups, and REAPER's autosave backups.
local COPIES = { backups = true, Backups = true }

local function walk(fs, dir, visit, prune)
  for _, e in ipairs(entries(fs, dir)) do
    local p = dir .. "/" .. e.name
    visit(p, e)
    if e.is_dir and not (prune and COPIES[e.name]) then walk(fs, p, visit, prune) end
  end
end

-- check(fs, band, band_folder) -> list of { code =, path = (relative to the band folder), detail =, fix = }
function M.check(fs, band, band_folder)
  local problems = {}
  local function rel(p) return path.relative(band_folder, p) or p end
  local function add(code, p, detail, fix, severity)
    problems[#problems + 1] = { code = code, path = rel(p), detail = detail, fix = fix, severity = severity or "problem" }
  end

  local master_root = band_folder .. "/" .. band.locations.master
  local pub_root = band_folder .. "/" .. band.locations.publications
  local prop_root = band_folder .. "/" .. band.locations.proposals
  local libraries = bandfile.libraries(band)
  local library_ids = {}
  for _, l in ipairs(libraries) do library_ids[l.id] = l end

  -- 1. songs in the master area: registered? duplicate ids? media in use?
  local reg = registry.load(fs, registry.file(band, band_folder)) or registry.empty()
  local ids_seen = {}
  local song_dirs = {}
  walk(fs, master_root, function(p, e)
    if e.is_dir and fs.exists(p .. "/" .. songfile.FILENAME) then song_dirs[#song_dirs + 1] = p end
  end, true)
  for _, dir in ipairs(song_dirs) do
    local song = songfile.read(fs, dir)
    if song then
      if ids_seen[song.id] then add("duplicate_song_id", dir, rel(ids_seen[song.id])) else ids_seen[song.id] = dir end
    end
  end
  local registered_paths = {}
  for _, entry in pairs(reg.songs) do
    registered_paths[entry.path] = true
    if not fs.exists(band_folder .. "/" .. entry.path .. "/" .. songfile.FILENAME) then add("registered_missing", band_folder .. "/" .. entry.path) end
  end
  walk(fs, master_root, function(p, e)
    if not e.is_dir and e.name:lower():match("%.rpp$") then
      local dir = path.dirname(p)
      if not fs.exists(dir .. "/" .. songfile.FILENAME) or not registered_paths[rel(dir)] then add("unregistered_project", p) end
    end
  end, true)
  for _, dir in ipairs(song_dirs) do
    local project
    for _, e in ipairs(entries(fs, dir)) do if not e.is_dir and e.name:lower():match("%.rpp$") then project = dir .. "/" .. e.name end end
    if project then -- (listing a folder that is not there simply gives nothing; "exists" is unreliable for folders)
      local used = {}
      local function use(text)
        for _, ref in ipairs(rpp.media_refs(text or "")) do used[path.normalize(inspect.resolve(dir, ref), "/")] = true end
      end
      use(fs.read_all(project))
      for _, b in ipairs(entries(fs, dir .. "/backups")) do -- an undo must still find its audio
        if b.is_dir then
          for _, f in ipairs(entries(fs, dir .. "/backups/" .. b.name)) do
            if not f.is_dir and f.name:lower():match("%.rpp$") then use(fs.read_all(dir .. "/backups/" .. b.name .. "/" .. f.name)) end
          end
        end
      end
      walk(fs, dir .. "/media", function(p, e)
        if not e.is_dir and e.name:lower() ~= "peaks" and not used[path.normalize(p, "/")] and not e.name:lower():match("%.reapeaks$") then
          add("unreferenced_media", p)
        end
      end)
    end
  end

  -- 2. publications and deliveries that are not finished
  walk(fs, pub_root, function(p, e)
    if e.is_dir and e.name:match("^r[1-9]%d*$") and #entries(fs, p) > 0 and not fs.exists(p .. "/" .. manifest.MARKER) then
      add("incomplete_pack", p) -- a revision folder with content but without its completion marker
    end
  end)
  walk(fs, prop_root, function(p, e)
    if e.is_dir and e.name:match("^d%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ") and path.basename(path.dirname(p)) == "outbox" then
      if not fs.exists(p .. "/" .. manifest.MARKER) then add("incomplete_pack", p) end
    end
  end)

  -- 3. things in the wrong area
  walk(fs, pub_root, function(p, e)
    if not e.is_dir and e.name:lower():match("%.rpp$") then add("wrong_area", p, "a project file among the publications") end
  end)
  for _, root in ipairs({ master_root, prop_root }) do
    walk(fs, root, function(p, e)
      if e.is_dir and e.name:match("^r[1-9]%d*$") and fs.exists(p .. "/" .. manifest.MARKER) and path.basename(path.dirname(p)) ~= "stems" then
        add("wrong_area", p, "a publication outside the publications")
      end
    end)
  end
  walk(fs, master_root, function(p, e)
    if e.is_dir and e.name:match("^d%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ") and fs.exists(p .. "/" .. manifest.MARKER) then
      add("wrong_area", p, "a delivery in the producer's area")
    end
  end)

  -- 4. proposals waiting in a closed cycle
  for _, member in ipairs(band.members) do
    local member_root = prop_root .. "/" .. member.id
    for _, lib in ipairs(libraries) do
      if lib.kind == "dated" then
        for _, c in ipairs(entries(fs, member_root .. "/" .. lib.id)) do
          if c.is_dir and cycles.valid_date(c.name) and not cycles.check_open(fs, band, band_folder, lib.id, c.name) then
            for _, s in ipairs(entries(fs, member_root .. "/" .. lib.id .. "/" .. c.name)) do
              if s.is_dir then
                local song_dir = member_root .. "/" .. lib.id .. "/" .. c.name .. "/" .. s.name
                local latest = deliveries.latest(fs, wm.outbox_dir(song_dir))
                if latest and deliveries.status(fs, cycles.dir(band, band_folder, "publications", lib.id, c.name) .. "/" .. s.name, latest.id) == "pending" then
                  add("proposal_in_closed_cycle", latest.dir)
                end
              end
            end
          end
        end
      end
    end
  end

  -- 5. names that do not follow the rules (library, cycle, song and member folders)
  local function check_level(dir, expect)
    for _, e in ipairs(entries(fs, dir)) do
      if e.is_dir then expect(dir .. "/" .. e.name, e.name) end
    end
  end
  local function song_name(p, name) if not slug.valid(name) then add("bad_name", p, "not a safe folder name") end end
  local function check_area(root, with_member)
    local function libraries_in(dir)
      check_level(dir, function(p, name)
        local lib = library_ids[name]
        if not lib then add("bad_name", p, "not one of the band's libraries"); return end
        if lib.kind == "dated" then
          check_level(p, function(cp, cname)
            if not cycles.valid_date(cname) then add("bad_name", cp, "not a date (year-month-day)") else check_level(cp, song_name) end
          end)
        else
          check_level(p, song_name)
        end
      end)
    end
    if with_member then
      local ids = {}
      for _, m in ipairs(band.members) do ids[m.id] = true end
      check_level(root, function(p, name)
        if not ids[name] then add("bad_name", p, "not a member of the band") else libraries_in(p) end
      end)
    else
      libraries_in(root)
    end
  end
  check_area(master_root, false); check_area(pub_root, false); check_area(prop_root, true)

  -- 6. leftovers nothing needs (safe to delete when the person agrees)
  walk(fs, band_folder, function(p, e)
    if not e.is_dir then
      local n = e.name:lower()
      if n:match("%.reapeaks$") or n:match("%.rpp%-bak$") or n == "registry.json.tmp" then add("stray_file", p, nil, "delete", "tidy") end
    end
  end)

  table.sort(problems, function(a, b)
    if a.code ~= b.code then return a.code < b.code end
    return a.path < b.path
  end)
  return problems
end

-- split(list) -> problems, tidy: real problems apart from harmless leftovers
function M.split(list)
  local problems, tidy = {}, {}
  for _, p in ipairs(list) do if p.severity == "tidy" then tidy[#tidy + 1] = p else problems[#problems + 1] = p end end
  return problems, tidy
end

-- fix(fs, band_folder, problem) -> true | nil, err: carries out the fix a problem offers, nothing else
function M.fix(fs, band_folder, problem)
  if problem.fix == "delete" and problem.code == "stray_file" then
    return fs.remove(band_folder .. "/" .. problem.path) and true or nil, "could not delete " .. problem.path
  end
  return nil, "no fix"
end

-- describe(S, problem) -> { what =, action =, text = }
function M.describe(S, problem)
  local vars = { path = problem.path, detail = problem.detail or "" }
  local what, action = S:t("check." .. problem.code .. ".what", vars), S:t("check." .. problem.code .. ".action", vars)
  return { what = what, action = action, text = what .. " " .. action }
end

return M
