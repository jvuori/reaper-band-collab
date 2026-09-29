local t = require("luatest")
local strings = require("muuri.strings")

local tables = {
  en = { hello = "Hello {name}", nested = { deep = "Deep" }, only_en = "English only" },
  fi = { hello = "Hei {name}", nested = { deep = "Syvä" } },
}

t.test("looks up by key in the chosen language, with dotted nested keys", function()
  local s = strings.new(tables, "fi")
  t.eq(s:t("hello", { name = "Ä" }), "Hei Ä")
  t.eq(s:t("nested.deep"), "Syvä")
  t.eq(strings.new(tables, "en"):t("nested.deep"), "Deep")
end)

t.test("a key missing in the chosen language falls back to English", function()
  local s = strings.new(tables, "fi")
  t.eq(s:t("only_en"), "English only")
  t.truthy(s:has("hello"))
  t.falsy(s:has("only_en"))
  t.truthy(s:has("only_en", "en"))
end)

t.test("a key missing everywhere is shown in brackets, never nil", function()
  t.eq(strings.new(tables, "fi"):t("nope"), "[nope]")
end)

t.test("placeholders: filled, repeated, and left visible when no value is given", function()
  local s = strings.new({ en = { a = "{x} and {x}", b = "{y}" } }, "en")
  t.eq(s:t("a", { x = 1 }), "1 and 1")
  t.eq(s:t("b", {}), "{y}")
  t.eq(s:t("b"), "{y}")
end)

t.test("an unknown language uses English", function()
  t.eq(strings.new(tables, "sv"):t("hello", { name = "X" }), "Hello X")
end)

t.test("keys and languages are listed sorted", function()
  local s = strings.new(tables, "en")
  t.eq(table.concat(s:keys("en"), ","), "hello,nested.deep,only_en")
  t.eq(table.concat(s:languages(), ","), "en,fi")
end)

t.test("load reads language files through the given loader", function()
  local s = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")
  t.truthy(s:has("err.missing_file.what", "fi"))
  t.truthy(s:has("err.missing_file.what", "en"))
  t.raises(function() strings.load(TEST_ROOT .. "/strings", { "xx" }, loadfile) end, "cannot load language xx")
end)

t.test("Finnish is the default when no language is chosen", function()
  t.eq(strings.new(tables):t("hello", { name = "X" }), "Hei X")
  t.eq(strings.new(tables).lang, "fi")
end)
