local store = require("sidenote.store")
local window = require("sidenote.window")

---Opens a note's prose for writing.
---
---Opens the real file rather than a scratch copy, so the user's own filetype
---plugins apply and saving lands exactly where the store expects it.
---@class sidenote.editor
local M = {}

---@type integer|nil
local current

---@return integer|nil winid
function M.winid()
    if current and vim.api.nvim_win_is_valid(current) then
        return current
    end
    return nil
end

---Open a note, returning the window showing it.
---
---The `toggle` style behaves as `split`, except that asking for the note
---already on show puts it away instead and returns nil.
---@param entry sidenote.session.Entry
---@param opts sidenote.EditorConfig
---@param filetype string
---@return integer|nil winid nil when a toggle closed the note
function M.open(entry, opts, filetype)
    local path = store.prose_target(entry.root, entry.id, filetype)

    if opts.style == "toggle" then
        local shown = M.winid()
        local name = shown and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(shown))
        if name and (vim.uv.fs_realpath(name) or name) == (vim.uv.fs_realpath(path) or path) then
            window.close(shown)
            current = nil
            return nil
        end
    end

    local bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
    -- From the file, not the parameter: a note written under an earlier
    -- `filetype` setting keeps the highlighting its extension names
    vim.bo[bufnr].filetype = vim.fn.fnamemodify(path, ":e")

    local existing = M.winid()
    if existing then
        vim.api.nvim_win_set_buf(existing, bufnr)
        if opts.focus then
            vim.api.nvim_set_current_win(existing)
        end
        return existing
    end

    current = window.open(bufnr, {
        style = opts.style == "toggle" and "split" or opts.style,
        position = opts.position,
        size = opts.size,
        focus = opts.focus,
    })
    return current
end

return M
