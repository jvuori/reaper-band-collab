-- Shared start-up for the UI scripts: finds the repository/package root from the script's own
-- location, makes lib/ requirable, and loads the string tables.
-- Usage in a script:
--   local dir = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
--   local boot = dofile(dir .. "/bootstrap.lua")(dir)
return function(script_dir)
  local root = script_dir:match("^(.*)[/\\][^/\\]*$") or (script_dir .. "/..")
  package.path = table.concat({ root .. "/lib/?.lua", script_dir .. "/?.lua", package.path }, ";")
  local strings = require("bandcollab.strings")
  return {
    root = root,
    dir = script_dir,
    strings = function(lang)
      return strings.load(root .. "/strings", { "en", "fi" }, loadfile, lang)
    end,
  }
end
