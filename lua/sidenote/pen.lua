local config = require("sidenote.config")

---The active pen: what a freshly captured note is inked with.
---
---Config seeds it (`vim.g.sidenote.pen`) and the session may change it;
---`vim.g.sidenote_state` mirrors the result for statuslines. Config is
---input and the state global is output — neither ever writes the other.
---@class sidenote.pen
local M = {}

---The word standing in for no pen wherever one is spoken to a reader.
---
---The name, not the placeholder: a column shows `record.NO_PEN`, but a ring, a
---menu row and a message all say this.
M.NONE = "none"

local NONE = M.NONE

---@type {pen: string|nil}|nil the pen picked up this session, nil until one is
local held

---Return the single pen held right now.
---
---A kind-split config holds no single pen, so the answer stays nil until one
---is chosen.
---@param cfg? sidenote.Config
---@return string|nil name pen held, nil when no single pen is up
function M.get(cfg)
    if held then
        return held.pen
    end
    local pen = (cfg or config.get()).pen
    return type(pen) == "string" and pen or nil
end

---Return the pen a fresh capture of `kind` picks up.
---
---A pen chosen this session wins outright — the user is holding it — then
---the config decides: one name inks both kinds, a table inks each its own.
---@param kind "note"|"todo"
---@param cfg? sidenote.Config
---@return string|nil name pen to ink with, nil when neither names one
function M.for_kind(kind, cfg)
    if held then
        return held.pen
    end
    local pen = (cfg or config.get()).pen
    if type(pen) == "table" then
        return pen[kind]
    end
    return pen
end

---Mirror the active pen into the read-only state global.
---@param cfg sidenote.Config
local function sync(cfg)
    local state = vim.g.sidenote_state or {}
    state.pen = M.get(cfg) or ""
    vim.g.sidenote_state = state
end

---List what the pen rotates through, none first and the pens sorted after.
---@param cfg? sidenote.Config
---@return string[] names with "none" standing in for no pen
function M.ring(cfg)
    local names = vim.tbl_keys((cfg or config.get()).pens)
    table.sort(names)
    table.insert(names, 1, NONE)
    return names
end

---Pick the active pen, nil or `"none"` putting every pen down.
---@param name string|nil
---@param cfg? sidenote.Config
---@return boolean ok
---@return string|nil err
function M.set(name, cfg)
    cfg = cfg or config.get()
    if name == NONE then
        name = nil
    end
    if name ~= nil and not cfg.pens[name] then
        return false,
            ("unknown pen %q; expected one of %s"):format(name, table.concat(M.ring(cfg), ", "))
    end
    held = { pen = name }
    sync(cfg)
    return true, nil
end

---Rotate the active pen one step through the ring.
---@param cfg? sidenote.Config
---@return string current the name landed on, "none" for no pen
function M.cycle(cfg)
    cfg = cfg or config.get()
    local ring = M.ring(cfg)
    local now = M.get(cfg) or NONE
    local at = 1
    for i, name in ipairs(ring) do
        if name == now then
            at = i
        end
    end
    local turned = ring[at % #ring + 1]
    M.set(turned, cfg)
    return turned
end

---Forget the session's choice, falling back to the configured pen.
function M.reset()
    held = nil
end

return M
