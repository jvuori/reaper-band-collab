local t = require("luatest")
local block = require("bandcollab.startup_block")
local installer = require("bandcollab.guardian_install")
local memfs = require("memfs")

local PATH = "/home/x/.config/REAPER/Scripts/Band Collab/Band/guardian_watch.lua"

local function count(text, pattern) local n = 0; for _ in text:gmatch(pattern) do n = n + 1 end; return n end

t.test("installing into an empty file gives one block that loads the guardian", function()
  local text = block.install("", PATH)
  t.truthy(block.has(text))
  t.eq(count(text, "BEGIN bandcollab"), 1); t.eq(count(text, "END bandcollab"), 1)
  t.truthy(text:find(string.format("%q", PATH), 1, true))
  t.truthy(text:find("pcall(dofile", 1, true), "a broken guardian must not break REAPER's start-up")
end)

t.test("the user's own start-up code is kept, before and after", function()
  local mine = "-- my startup\nreaper.ShowConsoleMsg('hi')\n"
  local installed = block.install(mine, PATH)
  t.truthy(installed:sub(1, #mine) == mine, "the user's code must stay first and unchanged")
  t.truthy(block.has(installed))
  local tail = installed .. "\n-- more of mine\nlocal x = 1\n"
  t.truthy(tail:find("more of mine", 1, true))
  local cleaned = block.remove(tail)
  t.truthy(cleaned:find("my startup", 1, true)); t.truthy(cleaned:find("more of mine", 1, true))
  t.falsy(block.has(cleaned))
end)

t.test("installing twice changes nothing; a new location replaces the old path", function()
  local once = block.install("-- mine\n", PATH)
  t.eq(block.install(once, PATH), once)
  local moved = block.install(once, "C:\\Users\\Käyttäjä\\AppData\\Roaming\\REAPER\\Scripts\\g.lua")
  t.eq(count(moved, "BEGIN bandcollab"), 1)
  t.falsy(moved:find("Band Collab/Band", 1, true))
  t.truthy(moved:find("Käyttäjä", 1, true))
end)

t.test("removing the block gives back exactly what was there before", function()
  for _, original in ipairs({ "", "-- mine\n", "-- mine\nreaper.Foo()\n", "line without newline" }) do
    local installed = block.install(original, PATH)
    local back = block.remove(installed)
    t.eq(back, original == "line without newline" and "line without newline\n" or original, "for " .. string.format("%q", original))
  end
  t.eq(block.remove("nothing here\n"), "nothing here\n")
end)

t.test("a half-written block (no end marker) is left alone rather than guessed at", function()
  local broken = "-- before\n-- BEGIN bandcollab\ndo\n"
  t.falsy(block.has(broken))
  t.eq(block.remove(broken), broken)
end)

t.test("paths with quotes and backslashes are written safely", function()
  local weird = 'C:\\Users\\a "b"\\g.lua'
  local text = block.install("", weird)
  local chunk = assert(load(text:gsub("pcall%(dofile, ", "return (", 1):match("return %b()") or "return nil"))
  t.eq(chunk(), weird)
end)

t.test("enable and disable work on a start-up file, and leave nothing behind when it was ours alone", function()
  local fs = memfs.new()
  local file = installer.startup_file("/home/x/.config/REAPER")
  t.eq(file, "/home/x/.config/REAPER/Scripts/__startup.lua")
  t.falsy(installer.enabled(fs, file))
  t.truthy(installer.enable(fs, file, PATH))
  t.truthy(installer.enabled(fs, file))
  t.truthy(installer.disable(fs, file))
  t.falsy(fs.exists(file), "a file that only held our block is removed")

  fs.files[file] = "-- mine\nreaper.Foo()\n"
  installer.enable(fs, file, PATH)
  installer.disable(fs, file)
  t.eq(fs.files[file], "-- mine\nreaper.Foo()\n", "the user's file comes back exactly")
  t.truthy(installer.disable(fs, file), "disabling when it is not enabled is harmless")
  t.truthy(installer.disable(memfs.new(), file))
end)
