-- Settings that belong to one machine only (who am I, where is the band folder).
-- They are stored in REAPER's extended state, which REAPER saves in the resource folder,
-- so they survive restarts. Nothing here is synced or shared.
local M = {}

M.SECTION = "bandcollab"

local Settings = {}
Settings.__index = Settings

-- Backend for running inside REAPER.
function M.reaper_backend()
  return {
    get = function(key)
      if reaper.HasExtState(M.SECTION, key) then return reaper.GetExtState(M.SECTION, key) end
      return nil
    end,
    set = function(key, value)
      if value == nil then reaper.DeleteExtState(M.SECTION, key, true)
      else reaper.SetExtState(M.SECTION, key, value, true) end
    end,
  }
end

-- Backend for tests: a plain table.
function M.memory_backend(initial)
  local data = initial or {}
  return { get = function(key) return data[key] end, set = function(key, value) data[key] = value end, data = data }
end

function M.new(backend) return setmetatable({ backend = backend }, Settings) end

local function text(v) return type(v) == "string" and v ~= "" and v or nil end

function Settings:member() return text(self.backend.get("member")) end
function Settings:set_member(id) self.backend.set("member", text(id)) end
function Settings:band_folder() return text(self.backend.get("band_folder")) end
function Settings:set_band_folder(path) self.backend.set("band_folder", text(path)) end

-- True when both questions ("Kuka sinä olet?", "Missä bändikansio on?") have been answered.
function Settings:is_configured() return self:member() ~= nil and self:band_folder() ~= nil end

function Settings:clear()
  self.backend.set("member", nil)
  self.backend.set("band_folder", nil)
end

return M
