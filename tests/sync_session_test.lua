local t = require("luatest")
local sync_session = require("bandcollab.sync_session")
local strings = require("bandcollab.strings")
local memfs = require("memfs")

local S = strings.load(TEST_ROOT .. "/strings", { "en", "fi" }, loadfile, "fi")
local band = { members = {} }

-- fake operations: the panel logic is tested without REAPER
local function world(overrides)
  local state = { kind = "none", arriving = false, closed = false, proposal = nil }
  local env = { calls = {}, undo_from = nil }
  env.status = function()
    return { sync = { kind = state.kind, master_newer = state.kind == "down" or state.kind == "both", own_changed = state.kind == "up" or state.kind == "both" },
      arriving = state.arriving, closed = state.closed, proposal = state.proposal, latest = 4, base = 3 }
  end
  env.can_undo = function() return env.undo_from end
  env.fetch = function(_, _, _, _, o)
    env.calls[#env.calls + 1] = "fetch"
    o.yield(10, "/x/work/stems/r4/bass.wav")
    state.kind = "up"
    return env.fetch_result or { from = 3, to = 4, structure = { changed = false, reasons = {} } }
  end
  env.undo = function()
    env.calls[#env.calls + 1] = "undo"
    if not env.undo_from then return nil, "nothing_to_undo" end
    env.undo_from = nil
    return { restored = 3 }
  end
  env.preflight = function()
    env.calls[#env.calls + 1] = "preflight"
    return env.pre or { problems = {}, blocking = false, warnings = {} }
  end
  env.send = function(_, _, _, _, o)
    env.calls[#env.calls + 1] = "send"
    env.sent_with = o
    o.yield(5, "/x/own/drums/tracks.chunk")
    return { id = "d20260929T200000Z" }
  end
  env.fix_orphans = function() env.calls[#env.calls + 1] = "fix"; env.pre = { problems = {}, blocking = false, warnings = {} }; return 2 end
  env.save = function() env.calls[#env.calls + 1] = "save" end
  for k, v in pairs(overrides or {}) do env[k] = v end
  local ws = { proj = "PROJ", dir = "/d", state = { member = "eero" } }
  local s = sync_session.new(memfs.new(), band, "/band", S, ws, env)
  s:refresh()
  return s, env, state
end

local function drive(s) local n = 0; while not s:step() do n = n + 1; assert(n < 1000) end; return n end

t.test("only the meaningful directions are offered: all four states", function()
  local s, _, st = world()
  local function cards(kind) st.kind = kind; s:refresh(); return s:cards() end
  local none = cards("none");  t.truthy(none.nothing); t.falsy(none.fetch); t.falsy(none.propose)
  local down = cards("down");  t.truthy(down.fetch); t.falsy(down.propose); t.falsy(down.nothing)
  local up = cards("up");      t.falsy(up.fetch); t.truthy(up.propose); t.falsy(up.propose_waits)
  local both = cards("both");  t.truthy(both.fetch); t.truthy(both.propose); t.truthy(both.propose_waits, "fetching comes first")
end)

t.test("a newer version that is still arriving is said so, not treated as 'up to date'", function()
  local s, _, st = world()
  st.arriving = true; s:refresh()
  local c = s:cards()
  t.truthy(c.arriving); t.falsy(c.nothing)
end)

t.test("in a closed cycle proposing is not offered", function()
  local s, _, st = world()
  st.kind = "up"; st.closed = true; s:refresh()
  t.falsy(s:cards().propose); t.truthy(s:cards().closed)
end)

t.test("fetching runs in slices, reports the result, and refreshes the state afterwards", function()
  local s, env = world()
  local st = s.status
  s.env.status = (function(orig) return function(...) return orig(...) end end)(s.env.status)
  s:start_fetch()
  t.truthy(s:running())
  t.falsy(s:step())
  t.truthy(s.progress:find("bass.wav"))
  drive(s)
  t.falsy(s:running())
  t.truthy(s.result.ok); t.truthy(s.result.text:find("r4")); t.eq(s.result.warning, nil)
  t.eq(s:cards().propose, true, "after fetching, the member's own changes are the only thing left")
  t.eq(env.calls[1], "fetch")
end)

t.test("a structure change is warned about, in words", function()
  local s, env = world()
  env.fetch_result = { from = 3, to = 4, structure = { changed = true, reasons = { "length", "sections" } } }
  s:start_fetch(); drive(s)
  t.truthy(s.result.ok)
  t.truthy(s.result.warning:find("pituus, osiot", 1, true))
  t.truthy(s.result.warning:find("Rakenne muuttui"))
end)

t.test("a failed fetch is reported in plain words", function()
  local s = world({ fetch = function() return nil, "size_mismatch", "stems/bass.wav" end })
  s:start_fetch(); drive(s)
  t.falsy(s.result.ok)
  t.truthy(s.result.text:find("stems/bass.wav", 1, true))
  t.eq(s.result.code, "size_mismatch")
end)

t.test("undo works once, and says so when there is nothing to restore", function()
  local s, env = world()
  env.undo_from = 3; s:refresh()
  t.eq(s.undo_from, 3)
  t.truthy(s:undo())
  t.truthy(s.result.ok); t.truthy(s.result.text:find("Palautettu"))
  t.eq(s.undo_from, nil)
  t.falsy(s:undo())
  t.eq(s.result.code, "nothing_to_undo")
end)

t.test("nothing is sent while a blocking problem exists, and nothing starts", function()
  local s, env = world({ preflight = function() return { problems = { { code = "send_orphans", severity = "blocking", detail = 2, fix = "move_orphans" } }, blocking = true, warnings = {} } end })
  t.falsy(s:start_send())
  t.falsy(s:running())
  t.eq(s.result.code, "preflight_failed")
  local list = s:problems()
  t.eq(#list, 1); t.eq(list[1].fix, "move_orphans"); t.truthy(list[1].text:find("2 raitaa"))
  for _, call in ipairs(env.calls) do t.truthy(call ~= "send") end
end)

t.test("warnings must be confirmed before anything is sent", function()
  local s, env = world({ preflight = function() return { problems = { { code = "send_empty", severity = "warning" }, { code = "send_timing", severity = "warning" } }, blocking = false, warnings = { "send_empty", "send_timing" } } end })
  t.falsy(s:start_send()); t.eq(s.result.code, "preflight_needs_ack")
  s:acknowledge("send_empty", true)
  t.falsy(s:start_send(), "one confirmation of two is not enough")
  s:acknowledge("send_timing", true)
  t.truthy(s:start_send())
  drive(s)
  t.truthy(s.result.ok)
  t.eq(env.sent_with.acknowledged.send_empty, true)
end)

t.test("a proposal carries the trimmed note, and the form is cleared afterwards", function()
  local s, env = world()
  s.note.summary = "  Tiukennettu säkeistö  "; s.note.body = "  Uudet täytteet.  "
  t.truthy(s:start_send()); drive(s)
  t.eq(env.sent_with.note.summary, "Tiukennettu säkeistö"); t.eq(env.sent_with.note.body, "Uudet täytteet.")
  t.truthy(s.result.ok); t.truthy(s.result.text:find("lähetetty")); t.eq(s.result.delivery, "d20260929T200000Z")
  t.eq(s.note.summary, ""); t.eq(next(s.ack), nil)
end)

t.test("moving stray tracks in saves the workspace and checks again", function()
  local s, env = world({ preflight = function() return { problems = { { code = "send_orphans", severity = "blocking", detail = 2, fix = "move_orphans" } }, blocking = true, warnings = {} } end })
  s:check()
  local problem = s:problems()[1]
  local saved_env = env
  env.preflight = function() env.calls[#env.calls + 1] = "preflight"; return env.pre or { problems = { { code = "send_orphans", severity = "blocking", detail = 2, fix = "move_orphans" } }, blocking = true, warnings = {} } end
  t.truthy(s:apply_fix(problem))
  t.eq(env.calls[#env.calls - 2], "fix"); t.eq(env.calls[#env.calls - 1], "save"); t.eq(env.calls[#env.calls], "preflight")
  t.eq(#s:problems(), 0, "the problem is gone")
  t.truthy(s:start_send())
end)

t.test("the status line says when it was sent and whether it was taken in", function()
  local s, _, st = world()
  t.eq(s:proposal_text(), nil)
  st.proposal = { id = "d1", sent = "2026-09-29 21:40", status = "pending" }; s:refresh()
  t.truthy(s:proposal_text():find("2026-09-29 21:40", 1, true)); t.truthy(s:proposal_text():find("ei ole vielä käsitellyt"))
  st.proposal.status = "accepted"; s:refresh()
  t.truthy(s:proposal_text():find("ottanut sen mukaan"))
end)
