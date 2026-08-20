local config = require("sidenote.config")

---The active pen: what a freshly captured note is inked with.
---
---Config seeds it (`vim.g.sidenote.pen`) and the session may change it;
---`vim.g.sidenote_state` mirrors the result for statuslines. Config is
---input and the state global is output — neither ever writes the other.
---@class sidenote.pen
local M = {}

---@type string|nil pen chosen this session, meaningful only when chosen
local active

---@type boolean whether the session overrode the configured pen
local chosen = false

---The active pen's name, or nil when notes start penless.
---@param cfg? sidenote.Config
---@return string|nil
function M.get(cfg)
    if chosen then
        return active
    end
    return (cfg or config.get()).pen
end

---Mirror the active pen into the read-only state global.
---@param cfg sidenote.Config
local function sync(cfg)
    local state = vim.g.sidenote_state or {}
    state.pen = M.get(cfg) or ""
    vim.g.sidenote_state = state
end

---The ring the pen rotates through: none first, then the pens sorted.
---@param cfg? sidenote.Config
---@return string[] names with "none" standing in for no pen
function M.ring(cfg)
    local names = vim.tbl_keys((cfg or config.get()).pens or {})
    table.sort(names)
    table.insert(names, 1, "none")
    return names
end

---Pick the active pen, nil or `"none"` putting every pen down.
---@param name string|nil
---@param cfg? sidenote.Config
---@return boolean ok
---@return string|nil err
function M.set(name, cfg)
    cfg = cfg or config.get()
    if name == "none" then
        name = nil
    end
    if name ~= nil and not (cfg.pens or {})[name] then
        return false,
            ("unknown pen %q; expected one of %s"):format(name, table.concat(M.ring(cfg), ", "))
    end
    active, chosen = name, true
    sync(cfg)
    return true, nil
end

---Rotate the active pen one step through the ring.
---@param cfg? sidenote.Config
---@return string current the name landed on, "none" for no pen
function M.cycle(cfg)
    cfg = cfg or config.get()
    local ring = M.ring(cfg)
    local now = M.get(cfg) or "none"
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
    active, chosen = nil, false
end

return M
