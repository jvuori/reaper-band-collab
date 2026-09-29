-- Minimal test framework for pure-logic modules (no REAPER dependency).
local M = { tests = {} }

function M.test(name, fn)
  M.tests[#M.tests + 1] = { name = name, fn = fn }
end

local function fmt(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function M.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg and (msg .. ": ") or "") .. "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
  end
end

function M.truthy(v, msg)
  if not v then error(msg or "expected a truthy value", 2) end
end

function M.falsy(v, msg)
  if v then error(msg or "expected a falsy value", 2) end
end

function M.raises(fn, pattern)
  local ok, err = pcall(fn)
  if ok then error("expected an error, none raised", 2) end
  if pattern and not tostring(err):find(pattern) then
    error("error " .. fmt(tostring(err)) .. " does not match " .. fmt(pattern), 2)
  end
end

local skip_mt = {}

-- Marks the running test as skipped (for example, needs a runtime feature that is not available).
function M.skip(reason) error(setmetatable({ reason = reason }, skip_mt), 0) end

-- Runs all registered tests, returns passed, failed, a list of failures, and a list of skips.
function M.run()
  local passed, failed, failures, skipped = 0, 0, {}, {}
  for _, t in ipairs(M.tests) do
    local ok, err = pcall(t.fn)
    if ok then
      passed = passed + 1
    elseif getmetatable(err) == skip_mt then
      skipped[#skipped + 1] = t.name .. ": " .. err.reason
    else
      failed = failed + 1
      failures[#failures + 1] = t.name .. ": " .. tostring(err)
    end
  end
  M.tests = {}
  return passed, failed, failures, skipped
end

return M
