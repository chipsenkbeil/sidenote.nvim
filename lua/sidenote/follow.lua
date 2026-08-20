local config = require("sidenote.config")
local editor = require("sidenote.editor")

---Keeps the note editor pointed at the annotation under the cursor.
---
---One pinned window, re-pointed as the cursor crosses into another note —
---never focused, never duplicated. On unannotated code the panel keeps the
---last note it showed: a blanking panel is churn, and the context header is
---what keeps a held-over note legible as such.
---@class sidenote.follow
local M = {}

---@type integer|nil autocmd group while following, nil when off
local group

---@type string|nil annotation the panel currently shows
local shown

---@type sidenote.Config|nil configuration follow was enabled with
local held

---Entries for one buffer state, so a cursor move costs a lookup, not a
---resolution of the whole file.
---@type {bufnr: integer, tick: integer, entries: sidenote.session.Entry[]}|nil
local cached

---@return boolean
function M.active()
    return group ~= nil
end

---Point the panel at the note under the cursor, if any.
local function point()
    local win = editor.winid()
    if shown and not win then
        -- The user closed the panel; following them around would reopen it
        M.disable()
        vim.notify("sidenote: follow off")
        return
    end

    local sidenote = require("sidenote")
    local bufnr = vim.api.nvim_get_current_buf()
    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
    if not cached or cached.bufnr ~= bufnr or cached.tick ~= tick then
        cached = { bufnr = bufnr, tick = tick, entries = sidenote.entries(bufnr) }
    end

    local entry = sidenote.at_cursor(cached.entries)
    if not entry or entry.id == shown then
        return
    end

    -- The prose being left is flushed, so the store never lies to a reader
    if win then
        local leaving = vim.api.nvim_win_get_buf(win)
        if vim.bo[leaving].modified then
            vim.api.nvim_buf_call(leaving, function()
                vim.cmd("silent update")
            end)
        end
    end

    local cfg = held or config.get()
    shown = entry.id
    local note =
        vim.tbl_extend("keep", { source = vim.api.nvim_get_current_buf(), config = cfg }, entry)
    editor.open(note, vim.tbl_extend("force", cfg.editor, { focus = false }), cfg.filetype)
end

---Start following, pointing the panel at the cursor right away.
---@param cfg? sidenote.Config
function M.enable(cfg)
    if group then
        return
    end
    held = cfg
    group = vim.api.nvim_create_augroup("sidenote.follow", { clear = true })
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = group,
        desc = "Re-point the note editor at the annotation under the cursor",
        callback = point,
    })
    point()
end

function M.disable()
    if group then
        vim.api.nvim_del_augroup_by_id(group)
        group = nil
    end
    shown = nil
    held = nil
    cached = nil
end

---Flip following, returning the state it landed in.
---@param cfg? sidenote.Config
---@return boolean active
function M.toggle(cfg)
    if group then
        M.disable()
        return false
    end
    M.enable(cfg)
    return true
end

return M
