-- Prepares a band folder with a registered master song, and sets this REAPER profile up as member "eero".
-- Env: BANDCOLLAB_ROOT, E2E_BAND (band folder to create). Quits when done.
local root = assert(os.getenv("BANDCOLLAB_ROOT"))
local band_folder = assert(os.getenv("E2E_BAND"))
package.path = table.concat({ root .. "/lib/?.lua", package.path }, ";")
local fs = require("bandcollab.fs_std")
local bandfile = require("bandcollab.bandfile")
local songfile = require("bandcollab.songfile")
local ls = require("bandcollab.localsettings")

for _, d in ipairs({ "tuottaja", "julkaisut", "ehdotukset" }) do fs.mkdirs(band_folder .. "/" .. d) end
assert(bandfile.write(fs, band_folder, {
  schema = 1, name = "Example Band", language = "fi", producer = "aino",
  roles = { { id = "bass", label = "Basso" }, { id = "drums", label = "Rummut" } },
  members = { { id = "aino", name = "Aino", roles = { "bass" } }, { id = "eero", name = "Eero", roles = { "drums" } } },
  locations = { master = "tuottaja", publications = "julkaisut", proposals = "ehdotukset" },
}))
local dir = band_folder .. "/tuottaja/harjoitukset/2026-09-29/biisi"
fs.mkdirs(dir)
assert(songfile.write(fs, dir, { id = "s0123456789abcdef", title = "Biisi", slug = "biisi", library = "harjoitukset", cycle = "2026-09-29" }))
assert(fs.write_all(dir .. "/PAAVERSIO_biisi.rpp", '<REAPER_PROJECT 0.1 "7.0" 0\n>\n'))
local s = ls.new(ls.reaper_backend()); s:set_band_folder(band_folder); s:set_member("eero")
os.exit(0, true)
