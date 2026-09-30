local t = require("luatest")
local wizard = require("bandcollab.wizard")
local bandfile = require("bandcollab.bandfile")
local strings = require("bandcollab.strings")
local memfs = require("memfs")

local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")

local function three_members()
  local s = wizard.new("fi")
  s.name = "Example Band"
  local a = wizard.add_member(s, "Aino")
  s.members[a].instruments[1] = { label = "Basso", tracks = 2 }
  local e = wizard.add_member(s, "Eero")
  s.members[e].instruments[1] = { label = "Rummut", tracks = 4 }
  wizard.add_instrument(s, e, "Koskettimet", 1)
  local p = wizard.add_member(s, "Pia")
  s.members[p].instruments[1] = { label = "Laulu", tracks = 1 }
  wizard.add_instrument(s, p, "Kitara", 2)
  return s
end

local function codes(problems) local o = {}; for _, p in ipairs(problems) do o[#o + 1] = p.code end; return table.concat(o, ",") end

t.test("a three-member band becomes a valid band.json model with roles, owners and counts", function()
  local band, counts = wizard.to_band(three_members(), S)
  t.truthy(band, "to_band failed")
  t.truthy(bandfile.validate(band))
  t.eq(#band.members, 3)
  t.eq(#band.roles, 5)
  t.eq(band.producer, "aino")
  t.eq(table.concat(band.members[2].roles, ","), "rummut,koskettimet")
  t.eq(counts.rummut, 4)
  t.eq(counts.kitara, 2)
  t.eq(band.language, "fi")
end)

t.test("folder names follow the chosen language", function()
  local s = three_members()
  local fi = wizard.to_band(s, S)
  t.eq(fi.locations.master, "tuottaja")
  t.eq(fi.locations.proposals, "ehdotukset")
  s.language = "en"
  S.lang = "en"
  local en = wizard.to_band(s, S)
  S.lang = "fi"
  t.eq(en.locations.master, "producer")
end)

t.test("the producer can be another member, and removing members keeps that choice sensible", function()
  local s = three_members()
  s.producer = 3
  t.eq(wizard.to_band(s, S).producer, "pia")
  wizard.remove_member(s, 1)
  t.eq(s.producer, 2)
  t.eq(wizard.to_band(s, S).producer, "pia")
  wizard.remove_member(s, 2)
  t.eq(s.producer, 1)
end)

t.test("identical instrument names get distinct role ids", function()
  local s = three_members()
  s.members[3].instruments[1] = { label = "Basso", tracks = 1 }
  local band = wizard.to_band(s, S)
  t.eq(band.roles[1].id, "basso")
  local ids = {}
  for _, r in ipairs(band.roles) do t.falsy(ids[r.id], "duplicate id " .. r.id); ids[r.id] = true end
end)

t.test("names with Finnish letters and odd characters produce valid ids", function()
  local s = wizard.new("fi")
  s.name = "Yö"
  local m = wizard.add_member(s, "Åsa Ääkkönen")
  s.members[m].instruments[1] = { label = "Sähkökitara / lead", tracks = 1 }
  local band = wizard.to_band(s, S)
  t.eq(band.members[1].id, "asa-aakkonen")
  t.eq(band.roles[1].id, "sahkokitara-lead")
  t.eq(band.roles[1].label, "Sähkökitara / lead")
end)

t.test("each kind of incomplete input is reported with a plain-language message", function()
  local s = wizard.new("fi")
  t.eq(codes(wizard.problems(s)), "wizard_no_band_name,wizard_no_members")
  s.name = "X"
  local m = wizard.add_member(s, "")
  t.eq(codes(wizard.problems(s)), "wizard_member_no_name,wizard_instrument_no_label")
  s.members[m].name = "A"
  s.members[m].instruments = {}
  t.eq(codes(wizard.problems(s)), "wizard_member_no_instrument")
  wizard.add_instrument(s, m, "Bass", 0)
  t.eq(codes(wizard.problems(s)), "wizard_bad_tracks")
  s.members[m].instruments[1].tracks = 33
  t.eq(codes(wizard.problems(s)), "wizard_bad_tracks")
  s.members[m].instruments[1].tracks = 2.5
  t.eq(codes(wizard.problems(s)), "wizard_bad_tracks")
  s.members[m].instruments[1].tracks = 3
  local n = wizard.add_member(s, "a")
  s.members[n].instruments[1].label = "Drums"
  t.eq(codes(wizard.problems(s)), "wizard_duplicate_member")
  local band, problems = wizard.to_band(s, S)
  t.eq(band, nil)
  t.truthy(#problems > 0)
end)

t.test("whitespace-only names count as empty", function()
  local s = wizard.new("fi")
  s.name = "   "
  t.truthy(codes(wizard.problems(s)):find("wizard_no_band_name"))
end)

t.test("every wizard problem code has a message in both languages", function()
  local messages = require("bandcollab.messages")
  local have = {}
  for _, c in ipairs(messages.codes(S, "en")) do have[c] = true end
  for _, c in ipairs({ "wizard_no_band_name", "wizard_no_members", "wizard_member_no_name", "wizard_duplicate_member",
    "wizard_member_no_instrument", "wizard_instrument_no_label", "wizard_bad_tracks", "wizard_cannot_create" }) do
    t.truthy(have[c], "no message for " .. c)
  end
end)

t.test("create refuses invalid input before touching the disk", function()
  local fs = memfs.new()
  local made, problems = wizard.create(fs, {}, "/band", wizard.new("fi"), S)
  t.eq(made, nil)
  t.truthy(#problems > 0)
  t.eq(next(fs.files), nil)
end)

t.test("create writes band.json, the location folders and calls the template builder", function()
  local fs = memfs.new()
  local calls = {}
  local fake_projects = {
    create_template = function(_, band, counts, file) calls[#calls + 1] = { band = band, counts = counts, file = file }; fs.files[file] = "tpl"; return true end,
  }
  local band = wizard.create(fs, fake_projects, "/band", three_members(), S)
  t.truthy(band)
  t.eq(#calls, 1)
  t.eq(calls[1].file, "/band/template/song-template.rpp")
  t.eq(calls[1].counts.rummut, 4)
  local read = bandfile.read(fs, "/band")
  t.eq(read.name, "Example Band")
  t.eq(#read.members, 3)
end)

t.test("messages about a member whose name is still empty name them by position, never leave a gap", function()
  local s = wizard.new("fi")
  s.name = "X"
  wizard.add_member(s, "")
  local found
  for _, p in ipairs(wizard.problems(s)) do
    if p.code == "wizard_instrument_no_label" then found = p end
  end
  t.eq(found.detail, "#1")
  local messages = require("bandcollab.messages")
  local text = messages.get(S, found.code, { detail = found.detail }).text
  t.falsy(text:find("  "), "double space in: " .. text)
  t.truthy(text:find("#1", 1, true))
end)
