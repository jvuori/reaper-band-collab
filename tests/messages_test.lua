local t = require("luatest")
local strings = require("muuri.strings")
local messages = require("muuri.messages")
local manifest = require("muuri.manifest")

local s = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "en")

local function placeholders(text)
  local set = {}
  for name in text:gmatch("{([%w_]+)}") do set[name] = true end
  local out = {}
  for k in pairs(set) do out[#out + 1] = k end
  table.sort(out)
  return table.concat(out, ",")
end

t.test("every error message has a non-empty 'what' and 'action' in every language", function()
  for _, lang in ipairs({ "en", "fi" }) do
    local codes = messages.codes(s, lang)
    t.truthy(#codes > 0, "codes in " .. lang)
    for _, code in ipairs(codes) do
      for _, part in ipairs({ "what", "action" }) do
        local key = "err." .. code .. "." .. part
        t.truthy(s:has(key, lang), "missing " .. key .. " in " .. lang)
        t.truthy(#s.flat[lang][key] > 5, "too short: " .. key .. " in " .. lang)
      end
    end
  end
end)

t.test("both languages define the same error codes and the same placeholders", function()
  t.eq(table.concat(messages.codes(s, "en"), ","), table.concat(messages.codes(s, "fi"), ","))
  for _, code in ipairs(messages.codes(s, "en")) do
    for _, part in ipairs({ "what", "action" }) do
      local key = "err." .. code .. "." .. part
      t.eq(placeholders(s.flat.fi[key]), placeholders(s.flat.en[key]), "placeholders of " .. key)
    end
  end
end)

t.test("every manifest problem code and band error code has a message", function()
  local have = {}
  for _, c in ipairs(messages.codes(s, "en")) do have[c] = true end
  for _, c in ipairs(manifest.problems) do t.truthy(have[c], "no message for manifest problem " .. c) end
  for _, c in ipairs({ "band_unreadable", "band_invalid", "band_too_new" }) do t.truthy(have[c], "no message for " .. c) end
end)

t.test("get fills placeholders and joins what and action", function()
  local m = messages.get(s, "missing_file", { path = "media/a.wav" })
  t.truthy(m.what:find("media/a.wav", 1, true))
  t.eq(m.text, m.what .. " " .. m.action)
  s.lang = "fi"
  local fi = messages.get(s, "missing_file", { path = "media/a.wav" })
  s.lang = "en"
  t.truthy(fi.what:find("puuttuu"))
end)

t.test("from_problem uses the problem's path", function()
  local m = messages.from_problem(s, { code = "size_mismatch", path = "media/b.wav" })
  t.truthy(m.what:find("media/b.wav", 1, true))
end)
