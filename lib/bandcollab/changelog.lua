-- The per-song change log (a Markdown file), newest entry first. Only the producer's tool writes
-- it, so it cannot conflict when synced. Members read it in the panel or as a file.
local M = {}

-- now() -> { display = "2026-09-29 20:00", iso = "2026-09-29T20:00:00+03:00" } in local time
function M.now(time)
  local t = time or os.time()
  local zone = os.date("%z", t) -- "+0300"
  return {
    display = os.date("%Y-%m-%d %H:%M", t),
    iso = os.date("%Y-%m-%dT%H:%M:%S", t) .. zone:sub(1, 3) .. ":" .. zone:sub(4, 5),
  }
end

local function clock(seconds)
  seconds = math.floor(seconds + 0.5)
  return string.format("%d:%02d", seconds // 60, seconds % 60)
end
M.clock = clock

-- entry = {
--   kind = "publication" | "import" | "rehearsal", revision = n | nil, time = now(), actor = "Name",
--   note = { summary =, body = } | nil,
--   facts = { { key = "stems", vars = { n = 3 } }, ... },
--   structure = { changed = bool, reasons = { "length", ... } } | nil,
--   tasks = { { who = "Drums", text = "..." }, ... } | nil,
-- }
function M.render_entry(entry, S)
  local head = "## "
  if entry.revision then head = head .. "r" .. entry.revision .. " - " end
  head = head .. entry.time.display .. " - " .. S:t("log." .. entry.kind)
  if entry.actor and entry.actor ~= "" then head = head .. " (" .. entry.actor .. ")" end
  head = head .. " <!-- " .. entry.time.iso .. " -->"

  local lines = { head, "" }
  local note = entry.note
  if note and note.summary and note.summary ~= "" then
    lines[#lines + 1] = note.summary
    if note.body and note.body ~= "" then
      lines[#lines + 1] = ""
      lines[#lines + 1] = note.body
    end
    lines[#lines + 1] = ""
  end
  for _, f in ipairs(entry.facts or {}) do
    lines[#lines + 1] = "- " .. S:t("log.fact_" .. f.key, f.vars)
  end
  if entry.facts and #entry.facts > 0 then lines[#lines + 1] = "" end

  -- the attention line appears only when other members' work is affected
  if entry.structure and entry.structure.changed then
    local names = {}
    for _, r in ipairs(entry.structure.reasons) do names[#names + 1] = S:t("log.reason_" .. r) end
    lines[#lines + 1] = "> **" .. S:t("log.attention") .. ":** " .. S:t("log.attention_structure", { reasons = table.concat(names, ", ") })
    lines[#lines + 1] = ""
  end
  if entry.tasks and #entry.tasks > 0 then
    lines[#lines + 1] = "**" .. S:t("log.tasks") .. ":**"
    lines[#lines + 1] = ""
    for _, task in ipairs(entry.tasks) do lines[#lines + 1] = "- " .. task.who .. ": " .. task.text end
    lines[#lines + 1] = ""
  end
  while lines[#lines] == "" do lines[#lines] = nil end
  return table.concat(lines, "\n")
end

-- file_name(S) -> the log's file name in the band's language
function M.file_name(S) return S:t("log.filename") end

-- add(fs, file, title, entry, S) -> true | nil, err
-- Puts the entry at the top, below the file heading. A missing file is created; anything the
-- producer wrote by hand between the heading and the first entry is kept.
function M.add(fs, file, title, entry, S)
  local existing = fs.read_all(file)
  local block = M.render_entry(entry, S)
  local text
  if not existing or existing == "" then
    text = "# " .. S:t("log.title", { title = title }) .. "\n\n" .. block .. "\n"
  else
    local first = existing:find("\n## ", 1, true)
    if first then
      text = existing:sub(1, first) .. block .. "\n\n" .. existing:sub(first + 1)
    else
      text = existing:gsub("%s*$", "") .. "\n\n" .. block .. "\n"
    end
  end
  return fs.write_all(file, text)
end

return M
