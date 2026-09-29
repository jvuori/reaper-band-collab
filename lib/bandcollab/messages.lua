-- Plain-language messages: every error says what happened and suggests one next step.
-- Messages live in the string tables as err.<code>.what and err.<code>.action.
local M = {}

-- get(strings, code [, vars]) -> { code =, what =, action =, text = }
function M.get(strings, code, vars)
  local what = strings:t("err." .. code .. ".what", vars)
  local action = strings:t("err." .. code .. ".action", vars)
  return { code = code, what = what, action = action, text = what .. " " .. action }
end

-- from_problem(strings, problem) -> message for a manifest.verify problem record
function M.from_problem(strings, problem)
  return M.get(strings, problem.code, { path = problem.path })
end

-- codes(strings [, lang]) -> sorted list of error codes defined in a language
function M.codes(strings, lang)
  local seen, out = {}, {}
  for _, key in ipairs(strings:keys(lang or strings.lang)) do
    local code = key:match("^err%.([^.]+)%.")
    if code and not seen[code] then seen[code] = true; out[#out + 1] = code end
  end
  return out
end

return M
