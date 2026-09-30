-- The band setup wizard's logic: a plain data model that the UI edits, validation with
-- plain-language problems, and creation of band.json plus the band template.
-- Nothing here draws anything, so it can be tested without a window.
local slug = require("bandcollab.slug")
local bandfile = require("bandcollab.bandfile")
local projects_path = "template/song-template.rpp" -- kept in step with projects.TEMPLATE_PATH

local M = {}

M.MAX_TRACKS = 32

function M.new(language)
  return { name = "", language = language or "fi", producer = 1, members = {} }
end

function M.add_member(state, name)
  state.members[#state.members + 1] = { name = name or "", instruments = { { label = "", tracks = 1 } } }
  return #state.members
end

-- Removing a member before the producer shifts the producer's position; removing the producer
-- hands the role to whoever takes that position (or the last member).
function M.remove_member(state, index)
  local producer = state.producer
  table.remove(state.members, index)
  if index < producer then producer = producer - 1 end
  state.producer = math.min(math.max(1, producer), math.max(1, #state.members))
end

function M.add_instrument(state, member, label, tracks)
  local list = state.members[member].instruments
  list[#list + 1] = { label = label or "", tracks = tracks or 1 }
  return #list
end

function M.remove_instrument(state, member, index)
  table.remove(state.members[member].instruments, index)
end

local function trimmed(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- problems(state) -> list of { code =, member =, instrument =, detail = }; empty when ready.
-- Each code has an err.<code> message in the string tables.
function M.problems(state)
  local out = {}
  local function add(code, member, instrument, detail)
    out[#out + 1] = { code = code, member = member, instrument = instrument, detail = detail }
  end
  if trimmed(state.name) == "" then add("wizard_no_band_name") end
  if #state.members == 0 then add("wizard_no_members") end
  local seen = {}
  for mi, m in ipairs(state.members) do
    local name = trimmed(m.name)
    local who = name ~= "" and name or ("#" .. mi) -- shown in messages when the name is still empty
    if name == "" then
      add("wizard_member_no_name", mi)
    else
      local key = slug.slug(name)
      if seen[key] then add("wizard_duplicate_member", mi, nil, name) end
      seen[key] = true
    end
    if #m.instruments == 0 then add("wizard_member_no_instrument", mi, nil, who) end
    for ii, inst in ipairs(m.instruments) do
      if trimmed(inst.label) == "" then add("wizard_instrument_no_label", mi, ii, who) end
      local n = inst.tracks
      if math.type(n) ~= "integer" or n < 1 or n > M.MAX_TRACKS then
        add("wizard_bad_tracks", mi, ii, trimmed(inst.label) ~= "" and trimmed(inst.label) or ("#" .. ii))
      end
    end
  end
  return out
end

-- to_band(state, strings) -> band, counts | nil, problems
-- The band's folder names come from the string tables, so they follow the chosen language.
function M.to_band(state, strings)
  local problems = M.problems(state)
  if #problems > 0 then return nil, problems end
  local roles, members, counts = {}, {}, {}
  local role_ids, member_ids = {}, {}
  for _, m in ipairs(state.members) do
    local member_id = slug.unique(slug.slug(trimmed(m.name)), member_ids)
    member_ids[member_id] = true
    local owned = {}
    for _, inst in ipairs(m.instruments) do
      local label = trimmed(inst.label)
      local role_id = slug.unique(slug.slug(label), role_ids)
      role_ids[role_id] = true
      roles[#roles + 1] = { id = role_id, label = label }
      counts[role_id] = inst.tracks
      owned[#owned + 1] = role_id
    end
    members[#members + 1] = { id = member_id, name = trimmed(m.name), roles = owned }
  end
  local lang_strings = strings
  local function place(key) return slug.slug(lang_strings:t("wizard.location_" .. key)) end
  local band = {
    schema = bandfile.SCHEMA,
    name = trimmed(state.name),
    language = state.language,
    producer = members[state.producer] and members[state.producer].id or members[1].id,
    roles = roles,
    members = members,
    locations = { master = place("master"), publications = place("publications"), proposals = place("proposals") },
  }
  local ok, code, detail = bandfile.validate(band)
  if not ok then return nil, { { code = code, detail = detail } } end
  return band, counts
end

-- create(fs, projects, folder, state, strings) -> band | nil, problems-or-error
-- Writes band.json and the location folders, then the band template.
function M.create(fs, projects, folder, state, strings)
  local band, counts = M.to_band(state, strings)
  if not band then return nil, counts end
  local dirs = { folder, folder .. "/" .. band.locations.master, folder .. "/" .. band.locations.publications,
    folder .. "/" .. band.locations.proposals }
  for _, d in ipairs(dirs) do
    if not fs.mkdirs(d) then return nil, { { code = "wizard_cannot_create", detail = d } } end
  end
  local ok, code, detail = bandfile.write(fs, folder, band)
  if not ok then return nil, { { code = code, detail = detail } } end
  local made, err = projects.create_template(fs, band, counts, folder .. "/" .. projects_path)
  if not made then return nil, { { code = "wizard_cannot_create", detail = err } } end
  return band
end

return M
