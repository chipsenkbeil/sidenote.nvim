---Public Lua API.
---@class sidenote
local M = {}

---@return sidenote.Config
local function config()
    local cfg, err = require("sidenote.config").get()
    if err then
        vim.notify("sidenote: " .. err, vim.log.levels.WARN)
    end
    return cfg
end

---Open a fresh note for writing, seeded by the user's template.
---
---The seed goes into the buffer alone, never the file: the prose file stays
---empty until the user's own `:write`, which is what invariant 3 means.
---@param result sidenote.capture.Result
---@param cfg sidenote.Config
local function compose(result, cfg)
    local where = vim.tbl_extend("force", cfg.editor, { focus = true })
    local winid =
        require("sidenote.editor").open({ root = result.root, id = result.id }, where, cfg.filetype)
    if not winid or not cfg.template then
        return
    end

    local rec = require("sidenote.store").read(result.root, result.id)
    if not rec then
        return
    end
    local ok, lines = pcall(cfg.template, {
        path = rec.path,
        filetype = cfg.filetype,
        scope = rec.scope,
        line_start = rec.line_start,
        line_end = rec.line_end,
        text = rec.text,
    })
    if not ok then
        vim.notify("sidenote: template failed: " .. tostring(lines), vim.log.levels.WARN)
        return
    end
    if type(lines) == "table" and #lines > 0 then
        vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(winid), 0, -1, false, lines)
    end
end

---Annotate the current buffer and open the new note for writing.
---@param opts sidenote.capture.Opts
---@return sidenote.capture.Result|nil
---@return string|nil err
function M.add(opts)
    local result, err = require("sidenote.capture").run(vim.api.nvim_get_current_buf(), opts)
    if result then
        compose(result, (opts and opts.config) or config())
    end
    return result, err
end

---Re-resolve and repaint a buffer's annotations.
---@param bufnr? integer defaults to the current buffer
---@return integer placed
function M.refresh(bufnr)
    return require("sidenote.session").refresh(bufnr or vim.api.nvim_get_current_buf())
end

---Every annotation targeting a buffer, resolved against its current text.
---@param bufnr? integer defaults to the current buffer
---@return sidenote.session.Entry[]
function M.entries(bufnr)
    return require("sidenote.session").entries(bufnr or vim.api.nvim_get_current_buf())
end

---Annotation whose range holds the cursor line, or nil when none does.
---@return sidenote.session.Entry|nil
function M.at_cursor()
    local line = vim.fn.line(".")
    for _, entry in ipairs(M.entries()) do
        if entry.line_start and line >= entry.line_start and line <= entry.line_end then
            return entry
        end
    end
    return nil
end

---@class sidenote.BrowseOpts
---@field bufnr? integer source buffer, defaulting to the current one
---@field filter? sidenote.browser.Filter which annotations survive into the listing

---Open the editable listing of this file's annotations.
---@param opts? sidenote.BrowseOpts
---@return integer|nil browser
---@return string|nil err
function M.browse(opts)
    opts = opts or {}
    return require("sidenote.browser").open(opts.bufnr or vim.api.nvim_get_current_buf(), {
        config = config(),
        filter = opts.filter,
    })
end

---@class sidenote.BrowseProjectOpts
---@field path? string any file inside the project, defaulting to the current one
---@field filter? sidenote.browser.Filter which annotations survive into the listing

---Open the editable listing of every annotation in the project.
---@param opts? sidenote.BrowseProjectOpts
---@return integer|nil browser
---@return string|nil err
function M.browse_project(opts)
    opts = opts or {}
    local from = opts.path
    if not from or from == "" then
        from = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    end
    if from == "" then
        from = vim.fn.getcwd()
    end
    return require("sidenote.browser").open_project(from, {
        config = config(),
        filter = opts.filter,
    })
end

---Show an annotation in the configured preview surface.
---@param entry sidenote.session.Entry
---@param cfg sidenote.Config
local function preview(entry, cfg)
    require("sidenote.preview").show(entry, {
        style = cfg.preview.style,
        max_lines = cfg.preview.max_lines,
        filetype = cfg.filetype,
        bufnr = vim.api.nvim_get_current_buf(),
    })
end

---Glance at the annotation under the cursor without leaving the code.
---@return boolean shown
function M.view()
    local entry = M.at_cursor()
    if not entry then
        return false
    end
    preview(entry, config())
    return true
end

---Open the annotation under the cursor for writing.
---@return boolean opened
function M.open()
    local entry = M.at_cursor()
    if not entry then
        return false
    end
    local cfg = config()
    local editor = vim.tbl_extend("force", cfg.editor, { focus = true })
    require("sidenote.editor").open(entry, editor, cfg.filetype)
    return true
end

---Jump to an adjacent annotation and preview it in one action.
---
---The fused motion is what makes the preview feel live, which is why no
---cursor-following machinery is needed.
---@param direction "next"|"prev"
---@return boolean moved
local function jump(direction)
    local entries = M.entries()
    local target = require("sidenote.navigate")[direction](entries, vim.fn.line("."))
    if not target then
        return false
    end

    vim.api.nvim_win_set_cursor(0, { target.line_start, 0 })
    preview(target, config())
    return true
end

---Jump to the next annotation and preview it.
---@return boolean moved
function M.next()
    return jump("next")
end

---Jump to the previous annotation and preview it.
---@return boolean moved
function M.prev()
    return jump("prev")
end

return M
