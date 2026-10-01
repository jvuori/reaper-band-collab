local t = require("luatest")
local inbox = require("bandcollab.inbox")
local manifest = require("bandcollab.manifest")
local json = require("bandcollab.json")
local memfs = require("memfs")

local band = {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" }, { id = "drums", label = "Rummut" } },
  members = { { id = "aino", name = "Aino", roles = { "bass" } }, { id = "eero", name = "Eero", roles = { "drums" } } },
  locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" },
  libraries = { { id = "harjoitukset", label = "Harjoitukset", kind = "dated" }, { id = "levytys", label = "Levytys", kind = "flat" } },
}
local PUB = "/band/julkaisut/harjoitukset/2026-09-29/biisi"

local function publications(fs, up_to)
  for n = 1, up_to do
    local dir = PUB .. "/r" .. n
    fs.files[dir .. "/a.wav"] = "x" .. n
    manifest.write(fs, dir, manifest.build(fs, dir, { created = "T" }))
  end
end

local function delivery(fs, member, id, base, sent, note, opts)
  opts = opts or {}
  local dir = "/band/ehdotukset/" .. member .. "/harjoitukset/2026-09-29/biisi/outbox/" .. id
  fs.files[dir .. "/own/x/tracks.chunk"] = "<TRACK\n>"
  fs.files[dir .. "/delivery.json"] = json.encode({ schema = 1, song = { id = "s0123456789abcdef", title = "Yö kuka minä" }, member = member, base_revision = base, created = sent, note = note })
  if not opts.unfinished then manifest.write(fs, dir, manifest.build(fs, dir, { created = "T" })) end
  return dir
end

t.test("proposals made against r5 and r8, with the master at r8: only the older base is flagged", function()
  local fs = memfs.new()
  publications(fs, 8)
  delivery(fs, "eero", "d20260929T200000Z", 5, "2026-09-29T20:00:00+03:00", { summary = "Tiukennettu säkeistö 2" })
  delivery(fs, "aino", "d20260929T210000Z", 8, "2026-09-29T21:00:00+03:00", { summary = "Uusi basso" })
  local r = inbox.list(fs, band, "/band")
  t.eq(#r.pending, 2); t.eq(#r.accepted, 0); t.eq(#r.arriving, 0)
  local first, second = r.pending[1], r.pending[2]
  t.eq(first.member, "eero"); t.eq(first.base, 5); t.eq(first.current, 8); t.truthy(first.outdated)
  t.eq(second.member, "aino"); t.eq(second.base, 8); t.falsy(second.outdated)
end)

t.test("each row shows who, when, what song and the note", function()
  local fs = memfs.new()
  publications(fs, 3)
  delivery(fs, "eero", "d20260929T204100Z", 3, "2026-09-29T20:41:00+03:00", { summary = "Tiukennettu säkeistö 2", body = "Uudet täytteet." })
  local e = inbox.list(fs, band, "/band").pending[1]
  t.eq(e.member_name, "Eero"); t.eq(e.sent, "2026-09-29 20:41"); t.eq(e.title, "Yö kuka minä")
  t.eq(e.slug, "biisi"); t.eq(e.library, "harjoitukset"); t.eq(e.cycle, "2026-09-29")
  t.eq(e.note.summary, "Tiukennettu säkeistö 2"); t.eq(e.note.body, "Uudet täytteet.")
  t.eq(e.delivery, "d20260929T204100Z"); t.eq(e.status, "pending")
end)

t.test("a member's newer delivery supersedes the older one, which is not listed separately", function()
  local fs = memfs.new()
  publications(fs, 2)
  delivery(fs, "eero", "d20260929T200000Z", 2, "2026-09-29T20:00:00+03:00", { summary = "first" })
  delivery(fs, "eero", "d20260929T213000Z", 2, "2026-09-29T21:30:00+03:00", { summary = "second" })
  local r = inbox.list(fs, band, "/band")
  t.eq(#r.pending, 1)
  t.eq(r.pending[1].note.summary, "second"); t.eq(r.pending[1].superseded, 1)
end)

t.test("a delivery the producer has taken in moves to the accepted list", function()
  local fs = memfs.new()
  publications(fs, 2)
  delivery(fs, "eero", "d20260929T200000Z", 2, "2026-09-29T20:00:00+03:00", { summary = "in" })
  fs.files[PUB .. "/imports.json"] = json.encode({ schema = 1, imports = { { delivery = "d20260929T200000Z", member = "eero", at = "T" } } })
  local r = inbox.list(fs, band, "/band")
  t.eq(#r.pending, 0); t.eq(#r.accepted, 1); t.eq(r.accepted[1].status, "accepted")
end)

t.test("a delivery still being copied is reported as arriving, never as a proposal", function()
  local fs = memfs.new()
  publications(fs, 2)
  delivery(fs, "eero", "d20260929T200000Z", 2, "2026-09-29T20:00:00+03:00", { summary = "done" })
  delivery(fs, "eero", "d20260929T220000Z", 2, "2026-09-29T22:00:00+03:00", { summary = "half" }, { unfinished = true })
  local r = inbox.list(fs, band, "/band")
  t.eq(#r.pending, 1); t.eq(r.pending[1].note.summary, "done")
  t.eq(#r.arriving, 1); t.eq(r.arriving[1].delivery, "d20260929T220000Z")
  local only = memfs.new()
  publications(only, 2)
  delivery(only, "eero", "d20260929T220000Z", 2, "2026-09-29T22:00:00+03:00", {}, { unfinished = true })
  local r2 = inbox.list(only, band, "/band")
  t.eq(#r2.pending, 0); t.eq(#r2.arriving, 1)
end)

t.test("proposals are listed oldest first, across members and songs, in dated and flat libraries", function()
  local fs = memfs.new()
  publications(fs, 1)
  delivery(fs, "eero", "d20260929T230000Z", 1, "2026-09-29T23:00:00+03:00", { summary = "late" })
  delivery(fs, "aino", "d20260929T180000Z", 1, "2026-09-29T18:00:00+03:00", { summary = "early" })
  local flat = "/band/ehdotukset/eero/levytys/virallinen/outbox/d20260930T090000Z"
  fs.files[flat .. "/own/x/tracks.chunk"] = "<TRACK\n>"
  fs.files[flat .. "/delivery.json"] = json.encode({ schema = 1, song = { title = "Virallinen" }, member = "eero", base_revision = 1, created = "2026-09-30T09:00:00+03:00" })
  manifest.write(fs, flat, manifest.build(fs, flat, { created = "T" }))
  local r = inbox.list(fs, band, "/band")
  local order = {}
  for _, e in ipairs(r.pending) do order[#order + 1] = e.member .. ":" .. e.slug end
  t.eq(table.concat(order, ","), "aino:biisi,eero:biisi,eero:virallinen")
  t.eq(r.pending[3].cycle, nil)
end)

t.test("an empty or missing proposals area gives empty lists", function()
  local r = inbox.list(memfs.new(), band, "/band")
  t.eq(#r.pending, 0); t.eq(#r.accepted, 0); t.eq(#r.arriving, 0)
end)

t.test("a delivery for a song nothing has been published for has no current revision and is not 'outdated'", function()
  local fs = memfs.new()
  delivery(fs, "eero", "d20260929T200000Z", 4, "2026-09-29T20:00:00+03:00", {})
  local e = inbox.list(fs, band, "/band").pending[1]
  t.eq(e.current, nil); t.falsy(e.outdated)
end)
