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
---empty until the user's own `:write`.
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
        local cfg = opts.config or config()
        local render = require("sidenote.render")

        -- A new mark left hidden by a toggle reads as a failed capture
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

---The buffer a command should act on: from inside a note, its own source.
---@param bufnr integer
---@return integer
local function dwim(bufnr)
    local note = vim.b[bufnr].sidenote
    if note and note.source and vim.api.nvim_buf_is_loaded(note.source) then
        return note.source
    end
    return bufnr
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
    return require("sidenote.browser").open(opts.bufnr or dwim(vim.api.nvim_get_current_buf()), {
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
        -- A listing widens to what it lists, and a note stands in for the
        -- file it annotates; neither buffer's own name is a project path
        local bufnr = vim.api.nvim_get_current_buf()
        local state = require("sidenote.browser").state(bufnr)
        from = state and state.path or vim.api.nvim_buf_get_name(dwim(bufnr))
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
        config = cfg,
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
    local note =
        vim.tbl_extend("keep", { source = vim.api.nvim_get_current_buf(), config = cfg }, entry)
    require("sidenote.editor").open(note, editor, cfg.filetype)
    return true
end

---@class sidenote.JumpOpts
---@field view? boolean also glance at the annotation you land on

---Jump to an adjacent annotation, previewing it only when asked.
---@param direction "next"|"prev"
---@param opts? sidenote.JumpOpts
---@return boolean moved
local function jump(direction, opts)
    local session = require("sidenote.session")

    -- Landing on a note the view hides reads as a broken jump
    local entries = require("sidenote.filter").narrow(M.entries(), session.viewing())
    local target = require("sidenote.navigate")[direction](entries, vim.fn.line("."))
    if not target then
        return false
    end

    vim.api.nvim_win_set_cursor(0, { target.line_start, 0 })
    if opts and opts.view then
        preview(target, config())
    end
    return true
end

---Jump to the next annotation; `view` also glances at it.
---@param opts? sidenote.JumpOpts
---@return boolean moved
function M.next(opts)
    return jump("next", opts)
end

---Jump to the previous annotation; `view` also glances at it.
---@param opts? sidenote.JumpOpts
---@return boolean moved
function M.prev(opts)
    return jump("prev", opts)
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

---This buffer's annotations as the window's location list.
---@param opts? sidenote.list.Opts
---@return integer listed
function M.loclist(opts)
    opts = opts or {}
    opts.bufnr = opts.bufnr or dwim(vim.api.nvim_get_current_buf())
    return require("sidenote.list").loclist(opts)
end

---The whole project's annotations as the quickfix list.
---@param opts? sidenote.list.Opts
---@return integer listed
function M.qflist(opts)
    opts = opts or {}
    opts.bufnr = opts.bufnr or dwim(vim.api.nvim_get_current_buf())
    return require("sidenote.list").qflist(opts)
end

---Delete the annotation under the cursor, after confirming.
---
---The confirmation quotes the prose it would destroy.
---@return boolean deleted
function M.delete()
    local entry = M.at_cursor()
    if not entry then
        vim.notify("sidenote: no annotation under the cursor", vim.log.levels.WARN)
        return false
    end
    local cfg = config()
    local store = require("sidenote.store")
    local summary = store.summary(entry.root, entry.id, cfg.filetype)
    local asked = ('sidenote: delete "%s"?'):format(summary or "no prose")
    if vim.fn.confirm(asked, "&Delete\n&Cancel", 2) ~= 1 then
        return false
    end
    store.delete(entry.root, entry.id, cfg.filetype)
    require("sidenote.session").refresh(vim.api.nvim_get_current_buf(), cfg)
    return true
end

---The active pen's name, or nil when new notes start penless.
---@return string|nil
function M.pen()
    return require("sidenote.pen").get(config())
end

---A statusline component: the active pen as a chip in its own ink, or "".
---
---```lua
----- Somewhere in a statusline expression
---vim.o.statusline = "%f %= %{%v:lua.require'sidenote'.statusline()%}"
---```
---@return string
function M.statusline()
    local cfg = config()
    local name = require("sidenote.pen").get(cfg)
    if not name then
        return ""
    end
    local group = cfg.pens[name]
    if not group then
        return name
    end
    return ("%%#%s# %s %%*"):format(group, name)
end

---Toggle the note editor following the cursor from note to note.
---@return boolean active
function M.follow()
    local active = require("sidenote.follow").toggle(config())
    vim.notify("sidenote: follow " .. (active and "on" or "off"))
    return active
end

return M
