local t = require("luatest")

t.test("eq passes on equal values", function() t.eq(1 + 1, 2) end)
t.test("raises catches errors and matches the message", function()
  t.raises(function() error("boom") end, "boom")
end)
t.test("truthy and falsy", function() t.truthy(true); t.falsy(nil) end)
