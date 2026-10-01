-- Locks and warnings are guardrails, not walls: a member can unlock things and a guardian cannot
-- stop anyone from saving. Nothing the tool says may claim otherwise (spec: project-guardian,
-- "Cannot block saving"). This reads every UI string in both languages.
local t = require("luatest")
local strings = require("bandcollab.strings")

local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")

-- phrases that say editing, moving or changing is impossible or prevented
local CLAIMS = {
  en = { "impossible", "cannot be edited", "can't be edited", "cannot edit", "cannot be changed", "can't be changed",
    "cannot be moved", "can't be moved", "unable to edit", "no way to edit", "prevents you", "is blocked", "are blocked", "not allowed to edit" },
  fi = { "mahdotonta", "ei voi muokata", "ei voi muuttaa", "ei voi siirtää", "ei pysty muokkaamaan", "ei saa muokata",
    "estetty", "on estetty", "estää sinua" },
}

t.test("no string claims that editing is impossible or prevented", function()
  for lang, phrases in pairs(CLAIMS) do
    for _, key in ipairs(S:keys(lang)) do
      local text = S.flat[lang][key]:lower()
      for _, phrase in ipairs(phrases) do
        t.falsy(text:find(phrase, 1, true), string.format("%s %s says %q: %s", lang, key, phrase, S.flat[lang][key]))
      end
    end
  end
end)

t.test("the guardian's warnings ask the person to close the project", function()
  for _, lang in ipairs({ "en", "fi" }) do
    for _, code in ipairs({ "master", "other_workspace", "unknown_owner" }) do
      local action = S.flat[lang]["guardian." .. code .. ".action"]
      t.truthy(action:lower():find("close") or action:lower():find("sulje"), lang .. " " .. code .. " should ask to close: " .. action)
    end
  end
end)

t.test("the workspace introduction describes the lock as protection against accidents", function()
  t.truthy(S.flat.en["ui.picker.intro"]:find("accident"))
  t.truthy(S.flat.fi["ui.picker.intro"]:find("vahingossa"))
end)
