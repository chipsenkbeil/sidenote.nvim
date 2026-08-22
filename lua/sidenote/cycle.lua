local config = require("sidenote.config")
local record = require("sidenote.core.record")
local render = require("sidenote.browser.render")
local store = require("sidenote.store")

---Rotates a note's kind, state or pen, from wherever the note is visible.
---
---Every surface that rotates one comes through here, so the rings and the
---write path can never drift apart.
---@class sidenote.cycle
local M = {}

---The values a field rotates through, in a stable order.
---
---A pen's ring opens with the `-` placeholder, so cycling can put the pen
---back down; the configured names follow, sorted.
---@param field "kind"|"state"|"pen"
---@param cfg sidenote.Config
---@return string[]
function M.ring(field, cfg)
    if field == "kind" then
        return record.KIND_NAMES
    end
    if field == "state" then
        return record.STATE_NAMES
    end
    local names = vim.tbl_keys(cfg.pens)
    table.sort(names)
    table.insert(names, 1, render.NO_PEN)
    return names
end

---@class sidenote.cycle.TurnOpts
---@field field "kind"|"state"|"pen" which ring to rotate
---@field offset integer 1 forward, -1 backward
---@field config sidenote.Config configuration holding the pens

---Rotate `rec`'s field one ring step, in place.
---@param rec sidenote.Annotation
---@param opts sidenote.cycle.TurnOpts
---@return string turned the value landed on, `-` for no pen
function M.turn(rec, opts)
    local ring = M.ring(opts.field, opts.config)
    local at = 1
    for i, name in ipairs(ring) do
        if name == (rec[opts.field] or render.NO_PEN) then
            at = i
        end
    end
    local turned = ring[(at - 1 + opts.offset) % #ring + 1]
    rec[opts.field] = turned ~= render.NO_PEN and turned or nil
    return turned
end

---@class sidenote.cycle.SetOpts
---@field field "kind"|"state"|"pen" which field to write
---@field value string|nil the new value, nil putting a pen down
---@field config sidenote.Config configuration for the repaint
---@field bufnr? integer annotated buffer to repaint, defaulting to current

---Set a field of a note and repaint what shows it.
---@param entry sidenote.session.Entry
---@param opts sidenote.cycle.SetOpts
---@return boolean ok false when the note is gone from the store or the write failed
function M.set(entry, opts)
    local rec = store.read(entry.root, entry.id)
    if not rec then
        return false
    end
    rec[opts.field] = opts.value
    local ok, err = store.update(entry.root, rec)
    if not ok then
        vim.notify("sidenote: " .. tostring(err), vim.log.levels.ERROR)
        return false
    end
    local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
    require("sidenote.session").refresh(bufnr, opts.config)
    require("sidenote.editor").redecorate_note(entry.id)
    return true
end

---@class sidenote.cycle.AtCursorOpts
---@field field "kind"|"state"|"pen" which ring to rotate
---@field offset integer 1 forward, -1 backward

---Rotate a field of the note under the cursor, telling the user where it landed.
---@param opts sidenote.cycle.AtCursorOpts
---@return boolean turned false when no note sits under the cursor or the write failed
function M.at_cursor(opts)
    local field, offset = opts.field, opts.offset
    local cfg = config.get()
    local entry = require("sidenote").at_cursor()
    if not entry then
        vim.notify("sidenote: no annotation under the cursor", vim.log.levels.WARN)
        return false
    end
    local rec = store.read(entry.root, entry.id)
    if not rec then
        return false
    end
    local turned = M.turn(rec, { field = field, offset = offset, config = cfg })
    if not M.set(entry, { field = field, value = rec[field], config = cfg }) then
        return false
    end
    vim.notify(("sidenote: %s %s"):format(field, turned))
    return true
end

return M
