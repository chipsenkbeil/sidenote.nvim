local buffer = require("sidenote.buffer")
local config = require("sidenote.config")
local hash = require("sidenote.core.hash")
local render = require("sidenote.browser.render")
local session = require("sidenote.session")
local store = require("sidenote.store")
local strategy = require("sidenote.store.strategy")

---@class sidenote.browser.State
---@field path string absolute path of the source file being browsed
---@field source integer buffer the annotations were resolved against
---@field config sidenote.Config configuration the browser was opened with
---@field rows sidenote.browser.Row[] what was rendered, in buffer order

---An oil-style editable listing of one file's annotations.
---@class sidenote.browser
local M = {}

---Prefix naming a browser buffer, followed by the absolute source path.
M.SCHEME = "sidenote://"

---Fold expression making each annotation one fold, opened by its header.
---
---Structure is read back out of the text, so nothing has to be kept in step
---with the buffer as it is edited.
M.FOLDEXPR = [[getline(v:lnum) =~ '^/' ? '>1' : '1']]

---@type table<integer, sidenote.browser.State>
local states = {}

---@param path string
---@return integer|nil bufnr
local function existing(path)
    local name = M.SCHEME .. path
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(bufnr) == name then
            return bufnr
        end
    end
    return nil
end

---@param entry sidenote.session.Entry
---@param filetype string
---@return string[]
local function prose_of(entry, filetype)
    local text = store.prose(entry.root, entry.id, filetype)
    return render.normalize(text and hash.split(text) or {})
end

---@param source integer
---@param cfg sidenote.Config
---@return sidenote.browser.Row[]
local function rows_for(source, cfg)
    local out = {}
    for i, entry in ipairs(session.entries(source, cfg)) do
        out[i] = { entry = entry, prose = prose_of(entry, cfg.filetype) }
    end
    return out
end

---Conceal and fold settings, all of which are window-local.
---
---Setting them on the buffer instead would silently do nothing and leave every
---id on screen.
---@param winid integer
local function dress(winid)
    local wo = vim.wo[winid]
    wo.conceallevel = 3
    wo.concealcursor = "nvic"
    wo.foldmethod = "expr"
    wo.foldexpr = M.FOLDEXPR
    -- An empty foldtext renders a closed fold as its own header line, conceal
    -- included, so a folded row reads exactly like an unfolded one
    wo.foldtext = ""
    wo.foldenable = true
    -- A note with no body is a one-line fold, which vim leaves open at the
    -- default of 1. Zero keeps "every annotation is a closed fold" true
    wo.foldminlines = 0
    wo.fillchars = vim.o.fillchars == "" and "fold: " or (vim.o.fillchars .. ",fold: ")
end

---Collapse every annotation, so the browser reads as an index.
---
---A fold created after 'foldlevel' was last set opens regardless of it, so
---this runs once the lines are in place rather than alongside the other
---window options.
---@param bufnr integer
local function close_all(bufnr)
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(winid) == bufnr then
            vim.wo[winid].foldlevel = 0
        end
    end
end

---@param bufnr integer
---@param state sidenote.browser.State
local function paint(bufnr, state)
    state.rows = rows_for(state.source, state.config)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, render.rows(state.rows))
    vim.bo[bufnr].modified = false
    states[bufnr] = state
    close_all(bufnr)
end

---Open the browser for a source buffer, in the current window.
---@param source integer
---@param cfg? sidenote.Config
---@return integer|nil bufnr
---@return string|nil err
function M.open(source, cfg)
    cfg = cfg or config.get()

    local target, target_err = buffer.target(source, { scope = "file" })
    if not target then
        return nil, target_err
    end
    local _, roots_err = strategy.resolve(target.path, cfg)
    if roots_err then
        return nil, roots_err
    end

    local bufnr = existing(target.path)
    if not bufnr then
        bufnr = vim.api.nvim_create_buf(true, false)
        vim.bo[bufnr].buftype = "acwrite"
        vim.bo[bufnr].swapfile = false
        vim.api.nvim_buf_set_name(bufnr, M.SCHEME .. target.path)
        vim.api.nvim_create_autocmd("BufWipeout", {
            buffer = bufnr,
            once = true,
            desc = "Drop the browser's diff baseline along with its buffer",
            callback = function()
                states[bufnr] = nil
            end,
        })
    end

    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.bo[bufnr].filetype = "sidenote"
    dress(winid)

    paint(bufnr, { path = target.path, source = source, config = cfg, rows = {} })
    return bufnr, nil
end

---What the browser last rendered, which is the baseline an edit is diffed
---against.
---@param bufnr integer
---@return sidenote.browser.State|nil
function M.state(bufnr)
    return states[bufnr]
end

---Re-render from the store, so the buffer shows what is now on disk.
---@param bufnr integer
---@return boolean rendered
function M.rerender(bufnr)
    local state = states[bufnr]
    if not state then
        return false
    end
    paint(bufnr, state)
    return true
end

return M
