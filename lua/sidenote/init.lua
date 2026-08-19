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

---Annotate the current buffer.
---@param opts sidenote.capture.Opts
---@return sidenote.capture.Result|nil
---@return string|nil err
function M.add(opts)
    return require("sidenote.capture").run(vim.api.nvim_get_current_buf(), opts)
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

---Annotation under the cursor, preferring the one whose range contains it.
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

---Open the editable listing of this file's annotations.
---@param bufnr? integer defaults to the current buffer
---@return integer|nil browser
---@return string|nil err
function M.browse(bufnr)
    return require("sidenote.browser").open(bufnr or vim.api.nvim_get_current_buf(), config())
end

---Open the editable listing of every annotation in the project.
---@param path? string any file inside the project, defaulting to the current one
---@return integer|nil browser
---@return string|nil err
function M.browse_project(path)
    local from = path
    if not from or from == "" then
        from = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    end
    if from == "" then
        from = vim.fn.getcwd()
    end
    return require("sidenote.browser").open_project(from, config())
end

---Glance at the annotation under the cursor without leaving the code.
---@return boolean shown
function M.view()
    local entry = M.at_cursor()
    if not entry then
        return false
    end
    local cfg = config()
    require("sidenote.preview").show(entry, cfg.preview, cfg.filetype)
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
    local cfg = config()
    require("sidenote.preview").show(target, cfg.preview, cfg.filetype)
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
