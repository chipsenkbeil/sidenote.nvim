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
    local bufnr = vim.api.nvim_get_current_buf()
    local result, err = require("sidenote.capture").run(bufnr, opts)
    if result then
        local cfg = (opts and opts.config) or config()
        -- A toggle hid the highlights for a moment; a capture is the moment
        -- ending, since a half-hidden new mark reads as a failed capture
        local render = require("sidenote.render")
        if render.suppressed(bufnr) then
            render.toggle(bufnr, cfg.indicator.highlight)
            require("sidenote.session").refresh(bufnr, cfg)
            vim.notify("sidenote: highlights shown")
        end
        compose(result, cfg)
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

---Annotation the cursor is in: the narrowest holding it, else a file-wide one.
---@param entries? sidenote.session.Entry[] list to select from, else this buffer's, resolved
---@return sidenote.session.Entry|nil
function M.at_cursor(entries)
    local line = vim.fn.line(".")
    local best, whole
    for _, entry in ipairs(entries or M.entries()) do
        if entry.line_start and line >= entry.line_start and line <= entry.line_end then
            -- Overlaps are legal; the most specific note is the one the
            -- cursor position is talking about
            local width = entry.line_end - entry.line_start
            if not best or width < best.line_end - best.line_start then
                best = entry
            end
        elseif not entry.line_start and entry.record.scope == "file" then
            whole = whole or entry
        end
    end
    return best or whole
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
        -- From inside a listing, widen what it lists: the listing's own
        -- buffer name is sidenote://…, which is no path at all
        local bufnr = vim.api.nvim_get_current_buf()
        local state = require("sidenote.browser").state(bufnr)
        from = state and state.path or vim.api.nvim_buf_get_name(bufnr)
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
    local note = vim.tbl_extend("keep", { source = vim.api.nvim_get_current_buf() }, entry)
    require("sidenote.editor").open(note, editor, cfg.filetype)
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

---Toggle this buffer's range highlights, the way spell is toggled.
---@return boolean|nil shown nil when the config pins them always or never
function M.toggle_highlight()
    local cfg = config()
    local bufnr = vim.api.nvim_get_current_buf()
    local shown = require("sidenote.render").toggle(bufnr, cfg.indicator.highlight)
    if shown == nil then
        vim.notify("sidenote: highlights are pinned " .. cfg.indicator.highlight)
        return nil
    end
    require("sidenote.session").refresh(bufnr, cfg)
    return shown
end

---Toggle the note editor following the cursor from note to note.
---@return boolean active
function M.follow()
    local active = require("sidenote.follow").toggle(config())
    vim.notify("sidenote: follow " .. (active and "on" or "off"))
    return active
end

return M
