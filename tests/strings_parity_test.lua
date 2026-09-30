local t = require("luatest")
local strings = require("bandcollab.strings")

local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")

local function placeholders(text)
  local set, out = {}, {}
  for name in text:gmatch("{([%w_]+)}") do set[name] = true end
  for k in pairs(set) do out[#out + 1] = k end
  table.sort(out)
  return table.concat(out, ",")
end

t.test("Finnish and English define exactly the same keys", function()
  local en, fi = {}, {}
  for _, k in ipairs(S:keys("en")) do en[k] = true end
  for _, k in ipairs(S:keys("fi")) do fi[k] = true end
  for k in pairs(en) do t.truthy(fi[k], "missing in fi: " .. k) end
  for k in pairs(fi) do t.truthy(en[k], "missing in en: " .. k) end
end)

t.test("each key uses the same placeholders in both languages", function()
  for _, k in ipairs(S:keys("en")) do
    t.eq(placeholders(S.flat.fi[k] or ""), placeholders(S.flat.en[k]), "placeholders of " .. k)
  end
end)

t.test("UI text only uses characters the UI font can draw (Latin-1)", function()
  for _, lang in ipairs({ "en", "fi" }) do
    for _, k in ipairs(S:keys(lang)) do
      for _, cp in utf8.codes(S.flat[lang][k]) do
        t.truthy(cp < 256, string.format("%s %s has U+%04X, which the UI font cannot draw", lang, k, cp))
      end
    end
  end
end)

t.test("no string is empty", function()
  for _, lang in ipairs({ "en", "fi" }) do
    for _, k in ipairs(S:keys(lang)) do t.truthy(#S.flat[lang][k] > 0, lang .. " " .. k) end
  end
end)
