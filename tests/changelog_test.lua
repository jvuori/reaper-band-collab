local t = require("luatest")
local changelog = require("bandcollab.changelog")
local strings = require("bandcollab.strings")
local memfs = require("memfs")

local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")
local EN = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")

local function time(display, iso) return { display = display, iso = iso } end

local publication = {
  kind = "publication", revision = 8, time = time("2026-10-02 21:40", "2026-10-02T21:40:00+03:00"), actor = "Aino",
  note = { summary = "Uusi miksaus. Basso nostettu, kertosäe pidennetty 4 tahtia.", body = "Kitarat vähän taaemmas." },
  facts = { { key = "stems", vars = { n = 3 } }, { key = "length", vars = { time = "3:08" } } },
  structure = { changed = true, reasons = { "length", "sections" } },
  tasks = { { who = "Rummut", text = "uusi otto kertosäkeeseen" } },
}

t.test("a publication entry matches the golden text", function()
  local expected = table.concat({
    "## r8 - 2026-10-02 21:40 - Julkaisu (Aino) <!-- 2026-10-02T21:40:00+03:00 -->",
    "",
    "Uusi miksaus. Basso nostettu, kertosäe pidennetty 4 tahtia.",
    "",
    "Kitarat vähän taaemmas.",
    "",
    "- 3 ryhmää julkaistu",
    "- Pituus: 3:08",
    "",
    "> **HUOM:** Rakenne muuttui (pituus, osiot). Hae pääversio ja tarkista omat raidat.",
    "",
    "**Tehtävää:**",
    "",
    "- Rummut: uusi otto kertosäkeeseen",
  }, "\n")
  t.eq(changelog.render_entry(publication, S), expected)
end)

t.test("an import entry shows both the sent and the imported time and the note", function()
  local entry = {
    kind = "import", revision = 7, time = time("2026-10-01 23:05", "2026-10-01T23:05:00+03:00"), actor = "Eero",
    note = { summary = "Tiukennettu säkeistö 2" },
    facts = { { key = "sent", vars = { time = "2026-10-01 21:40" } }, { key = "replaced", vars = { n = 2, role = "Rummut" } } },
  }
  local expected = table.concat({
    "## r7 - 2026-10-01 23:05 - Ehdotus tuotu (Eero) <!-- 2026-10-01T23:05:00+03:00 -->",
    "",
    "Tiukennettu säkeistö 2",
    "",
    "- Lähetetty: 2026-10-01 21:40",
    "- Korvattu: 2 raitaa (Rummut)",
  }, "\n")
  t.eq(changelog.render_entry(entry, S), expected)
end)

t.test("the attention line appears only for a change that affects other members", function()
  local ordinary = { kind = "publication", revision = 2, time = time("2026-10-02 21:40", "x"), actor = "Aino",
    note = { summary = "Pieni korjaus" }, structure = { changed = false, reasons = {} } }
  t.falsy(changelog.render_entry(ordinary, S):find("HUOM"))
  t.falsy(changelog.render_entry({ kind = "publication", revision = 1, time = time("d", "i") }, S):find("HUOM"))
  t.truthy(changelog.render_entry(publication, S):find("**HUOM:**", 1, true))
end)

t.test("tasks appear under their own heading, and only when there are some", function()
  local text = changelog.render_entry(publication, S)
  t.truthy(text:find("**Tehtävää:**", 1, true))
  t.truthy(text:find("- Rummut: uusi otto kertosäkeeseen", 1, true))
  local without = {}
  for k, v in pairs(publication) do without[k] = v end
  without.tasks = {}
  t.falsy(changelog.render_entry(without, S):find("Tehtävää"))
end)

t.test("an entry with no note and no facts is just its heading", function()
  local text = changelog.render_entry({ kind = "rehearsal", time = time("2026-09-29 20:00", "i"), actor = "Aino" }, S)
  t.eq(text, "## 2026-09-29 20:00 - Harjoitus vastaanotettu (Aino) <!-- i -->")
end)

t.test("English uses English words", function()
  local text = changelog.render_entry(publication, EN)
  t.truthy(text:find("Publication (Aino)", 1, true))
  t.truthy(text:find("**NOTE:** The structure changed (length, sections).", 1, true))
  t.truthy(text:find("**To do:**", 1, true))
end)

t.test("the log file is created with a heading and entries go on top, newest first", function()
  local fs = memfs.new()
  local file = "/band/tuottaja/harjoitukset/2026-09-29/biisi/MUUTOSLOKI.md"
  local first = { kind = "rehearsal", time = time("2026-09-29 20:00", "a"), actor = "Aino", note = { summary = "Alku" } }
  local second = { kind = "publication", revision = 1, time = time("2026-09-29 22:15", "b"), actor = "Aino", note = { summary = "Eka miksaus" } }
  t.truthy(changelog.add(fs, file, "Biisi", first, S))
  t.truthy(fs.files[file]:find("^# Biisi %- muutosloki\n\n## "))
  t.truthy(changelog.add(fs, file, "Biisi", second, S))
  local text = fs.files[file]
  local a, b = text:find("Eka miksaus", 1, true), text:find("Alku", 1, true)
  t.truthy(a and b and a < b, "the newer entry must come first")
  t.eq(select(2, text:gsub("\n## ", "")), 2)
end)

t.test("text the producer wrote by hand under the heading is kept", function()
  local fs = memfs.new({ ["/log.md"] = "# Biisi - muutosloki\n\nHuomioita: älä poista tätä.\n\n## 2026-09-01 10:00 - Julkaisu <!-- x -->\n\nVanha\n" })
  changelog.add(fs, "/log.md", "Biisi", { kind = "publication", revision = 2, time = time("2026-09-29 22:15", "b"), note = { summary = "Uusi" } }, S)
  local text = fs.files["/log.md"]
  t.truthy(text:find("Huomioita: älä poista tätä.", 1, true))
  t.truthy(text:find("Uusi", 1, true) < text:find("Vanha", 1, true))
  t.truthy(text:find("Huomioita", 1, true) < text:find("Uusi", 1, true))
end)

t.test("now() gives a display time and an ISO time with the offset", function()
  local n = changelog.now(0)
  t.truthy(n.display:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$"))
  t.truthy(n.iso:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d[+-]%d%d:%d%d$"))
end)

t.test("clock formats minutes and seconds", function()
  t.eq(changelog.clock(188), "3:08")
  t.eq(changelog.clock(59.6), "1:00")
  t.eq(changelog.clock(0), "0:00")
end)
