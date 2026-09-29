local t = require("luatest")
local json = require("muuri.json")

t.test("encodes scalars and nesting deterministically (sorted keys)", function()
  t.eq(json.encode({ b = 1, a = { 1, 2, { x = true } }, c = "z" }), '{"a":[1,2,{"x":true}],"b":1,"c":"z"}')
end)

t.test("empty containers: {} by default, [] when marked", function()
  t.eq(json.encode({}), "{}")
  t.eq(json.encode(json.array()), "[]")
  t.eq(json.encode({ list = json.array() }), '{"list":[]}')
end)

t.test("integers stay integers, floats keep precision", function()
  t.eq(json.encode({ n = 3 }), '{"n":3}')
  t.eq(json.encode({ n = 2.5 }), '{"n":2.5}')
  t.eq(math.type(json.decode("42")), "integer")
  t.eq(math.type(json.decode("42.0")), "float")
  t.eq(json.decode("-7"), -7)
  t.eq(json.decode("1e3"), 1000.0)
  t.eq(json.decode("[1.5e-2]")[1], 0.015)
end)

t.test("unicode: Finnish letters pass through, escapes decode, surrogate pairs combine", function()
  local s = "Yö äiti å"
  t.eq(json.encode({ s = s }), '{"s":"Yö äiti å"}')
  t.eq(json.decode('"Y\\u00f6 \\u00e4iti \\u00e5"'), s)
  t.eq(json.decode('"\\ud83c\\udfb8"'), "\u{1F3B8}")
  t.eq(json.decode(json.encode({ k = "\u{1F3B8}" })).k, "\u{1F3B8}")
  t.eq(json.decode(json.encode({ ["kappale ä"] = 1 }))["kappale ä"], 1)
end)

t.test("escapes: quotes, backslashes, control characters round trip", function()
  local s = 'a"b\\c\nd\te\1f'
  local enc = json.encode({ s = s })
  t.eq(enc, '{"s":"a\\"b\\\\c\\nd\\te\\u0001f"}')
  t.eq(json.decode(enc).s, s)
end)

t.test("round trip of a nested document is stable", function()
  local doc = { schema = 1, files = { { path = "a/b.wav", size = 123456789012, hash = "ab12" } }, ok = true, note = "Ääni" }
  local once = json.encode(doc)
  t.eq(json.encode(json.decode(once)), once)
end)

t.test("pretty printing is decodable and indented", function()
  local pretty = json.encode({ a = { 1, 2 }, b = {} }, { pretty = true })
  t.truthy(pretty:find("\n  \"a\": %["))
  t.eq(json.decode(pretty).a[2], 2)
end)

t.test("null is preserved as json.null", function()
  t.eq(json.decode('{"x":null}').x, json.null)
  t.eq(json.encode({ x = json.null }), '{"x":null}')
end)

t.test("whitespace, BOM and empty containers decode", function()
  t.eq(#json.decode(" \n [ ] "), 0)
  t.truthy(next(json.decode("{ }")) == nil)
  t.eq(json.decode("\239\187\191{\"a\":1}").a, 1)
end)

t.test("malformed input raises errors with line and column", function()
  local bad = {
    '{"a":1', '{"a":1,}', '[1,2,]', '{"a" 1}', '{a:1}', '"abc', '"\\x"', '[1 2]', '{"a":tru}',
    '01', '', '{"a":1} extra', '"\\ud83c"', '"tab\there"', '-', '[',
  }
  for _, text in ipairs(bad) do
    local v, err = json.try_decode(text)
    t.eq(v, nil, "should reject " .. string.format("%q", text))
    t.truthy(err:find("^json: "), "message prefix for " .. string.format("%q", text))
  end
  t.raises(function() json.decode('{\n  "a": ?\n}') end, "line 2, column 8")
end)

t.test("encoding rejects unsupported values", function()
  t.raises(function() json.encode({ f = function() end }) end, "cannot encode")
  t.raises(function() json.encode({ n = 0/0 }) end, "NaN")
  t.raises(function() json.encode({ [1.5] = 1 }) end, "keys")
  t.raises(function() json.encode({ s = "\255\254" }) end, "UTF%-8")
end)
