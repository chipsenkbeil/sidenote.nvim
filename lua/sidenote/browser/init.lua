local apply = require("sidenote.browser.apply")
local buffer = require("sidenote.buffer")
local config = require("sidenote.config")
local confirm = require("sidenote.browser.confirm")
local diff = require("sidenote.browser.diff")
local editor = require("sidenote.editor")
local hash = require("sidenote.core.hash")
-- `sidenote.render` paints status indicators, which is what it is doing here;
-- the browser's own renderer already owns the name
local indicator = require("sidenote.render")
local parse = require("sidenote.browser.parse")
local project = require("sidenote.store.project")
local render = require("sidenote.browser.render")
local scan = require("sidenote.scan")
local session = require("sidenote.session")
local store = require("sidenote.store")
local strategy = require("sidenote.store.strategy")
local window = require("sidenote.window")

---@class sidenote.browser.Filter
---@field status? sidenote.Status keep only annotations the resolver put here
---@field kind? "note"|"todo" keep only notes or only requests to act
---@field state? string keep only one lifecycle position

---@class sidenote.browser.State
---@field scope "file"|"project" how wide a set the listing covers
---@field path string absolute path of the source file, or of the project root
---@field source integer|nil buffer the annotations came from, absent for a project
---@field config sidenote.Config configuration the browser was opened with
---@field filter sidenote.browser.Filter which annotations survive into the listing
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

---@param name string full buffer name of a listing
---@return integer|nil bufnr
local function existing(name)
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

---Whether an entry passes the listing's filter.
---@param entry sidenote.session.Entry
---@param filter sidenote.browser.Filter
---@return boolean
local function survives(entry, filter)
    return (filter.status == nil or entry.status == filter.status)
        and (filter.kind == nil or entry.record.kind == filter.kind)
        and (filter.state == nil or entry.record.state == filter.state)
end

---Resolve whatever set the listing covers.
---
---A file listing resolves against its buffer, so unsaved edits count; a project
---listing resolves the whole store, preferring a loaded buffer where there is
---one.
---@param state sidenote.browser.State
---@return sidenote.browser.Row[]
local function rows_for(state)
    local entries = state.scope == "project"
            and scan.project({ path = state.path, config = state.config })
        or session.entries(state.source, state.config)

    -- Filtered rows are absent from the baseline too, not merely hidden: a
    -- write must never delete an annotation the listing did not show
    local out = {}
    for _, entry in ipairs(entries) do
        if survives(entry, state.filter) then
            out[#out + 1] = { entry = entry, prose = prose_of(entry, state.config.filetype) }
        end
    end
    return out
end

---Set a window option for the listing alone, never for the window itself.
---
---`scope = "local"` is what makes leaving free: vim reverts a local-scoped
---window option on its own the moment the window shows another buffer, under
---`:edit`, `nvim_win_set_buf` and `:bwipeout` alike. Nothing is saved, so
---nothing can fail to be given back.
---@param winid integer
---@param option string
---@param value boolean|integer|string
local function set_local(winid, option, value)
    vim.api.nvim_set_option_value(option, value, { win = winid, scope = "local" })
end

---Conceal and fold settings, all of which are window-local.
---
---Setting them on the buffer instead would silently do nothing and leave every
---id on screen.
---@param winid integer
local function configure(winid)
    set_local(winid, "conceallevel", 3)
    set_local(winid, "concealcursor", "nvic")
    set_local(winid, "foldmethod", "expr")
    set_local(winid, "foldexpr", M.FOLDEXPR)
    -- An empty foldtext renders a closed fold as its own header line, conceal
    -- included, so a folded row reads exactly like an unfolded one
    set_local(winid, "foldtext", "")
    set_local(winid, "foldenable", true)
    -- A note with no body is a one-line fold, which vim leaves open at the
    -- default of 1. Zero keeps "every annotation is a closed fold" true
    set_local(winid, "foldminlines", 0)
    set_local(
        winid,
        "fillchars",
        vim.o.fillchars == "" and "fold: " or (vim.o.fillchars .. ",fold: ")
    )
    -- A closed fold never wraps, so leaving wrap on would change a row's shape
    -- the moment it is expanded. Summaries are untruncated and can be long
    set_local(winid, "wrap", false)
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
            set_local(winid, "foldlevel", 0)
        end
    end
end

---@param bufnr integer
---@param state sidenote.browser.State
local function paint(bufnr, state)
    state.rows = rows_for(state)
    local lines, headers = render.rows(state.rows)

    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modified = false
    states[bufnr] = state

    -- Healthy is silent: the row itself says the note exists, so the gutter
    -- only earns ink when an anchor needs attention
    ---@type sidenote.render.Entry[]
    local marks = {}
    for i, row in ipairs(state.rows) do
        if row.entry.status ~= "attached" then
            marks[#marks + 1] = {
                id = row.entry.id,
                status = row.entry.status,
                line_start = headers[i],
                line_end = headers[i],
            }
        end
    end
    indicator.paint(bufnr, marks, { style = "sign" })
    close_all(bufnr)
end

---@param applied integer
---@param problems string[]
local function report(applied, problems)
    if #problems > 0 then
        vim.notify("sidenote: " .. table.concat(problems, "\n"), vim.log.levels.ERROR)
    elseif applied > 0 then
        local plural = applied == 1 and "" or "s"
        vim.notify(("sidenote: applied %d change%s"):format(applied, plural))
    end
end

---Move the cursor to whichever column `find` picks out.
---@param bufnr integer
---@param find fun(text: string, col: integer): integer|nil
local function step(bufnr, find)
    local winid = vim.api.nvim_get_current_win()
    local lnum, col = unpack(vim.api.nvim_win_get_cursor(winid))
    local text = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
    -- Cursor columns are 0-based bytes; parsed fields are 1-based
    local target = find(text, col + 1)
    if target then
        vim.api.nvim_win_set_cursor(winid, { lnum, target - 1 })
    end
end

---What `?` shows below the mappings themselves.
local HELP_FOOTER = {
    "",
    "  Folds are real: za, zR, zM and friends all work",
    "  Edit any column or prose line, then :w to apply",
    "  dd on a closed row deletes the whole note",
}

---Jump to the code a row's annotation is about, in this same window.
---
---The export gate's rule holds in the UI too: a note with no trusted position
---gets a message, never a guess at whatever now sits on its old lines.
---@param bufnr integer
local function visit(bufnr)
    local row = M.row_at(bufnr, vim.fn.line("."))
    local state = states[bufnr]
    if not row or not state then
        return
    end

    local rec = row.entry.record
    if not row.entry.line_start and rec.scope ~= "file" then
        vim.notify(
            "sidenote: no trusted position; the code no longer exists as written",
            vim.log.levels.WARN
        )
        return
    end

    local root = project.root(state.path)
    local path = rec.path:sub(1, 1) == "/" and rec.path
        or (root and (root .. "/" .. rec.path) or rec.path)
    if vim.fn.filereadable(path) ~= 1 then
        vim.notify(("sidenote: %s does not exist"):format(rec.path), vim.log.levels.WARN)
        return
    end

    vim.cmd.edit(vim.fn.fnameescape(path))
    if row.entry.line_start then
        vim.api.nvim_win_set_cursor(0, { row.entry.line_start, 0 })
    end
end

---Show the browser's own mappings, the way oil and lazy answer `?`.
---@param actions {lhs: string, desc: string}[]
local function help(actions)
    local lines = {}
    for _, action in ipairs(actions) do
        lines[#lines + 1] = ("  %-8s %s"):format(action.lhs, action.desc)
    end
    vim.list_extend(lines, HELP_FOOTER)
    local width = 0
    for _, line in ipairs(lines) do
        width = math.max(width, #line)
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].bufhidden = "wipe"

    local winid = window.open(bufnr, { style = "float", size = width + 2, focus = true })
    for _, lhs in ipairs({ "q", "<Esc>", "?" }) do
        vim.keymap.set("n", lhs, function()
            window.close(winid)
        end, { buffer = bufnr, nowait = true })
    end
end

---Mappings that live only inside a browser buffer, kept as data first.
---
---One list serves twice — the keymaps are built from it and `?` renders it —
---so the help can never drift from what the keys do. Fold verbs are
---deliberately absent: expansion is real folds, so `za`, `zR` and the user's
---own fold mappings already do the right thing.
---@param bufnr integer
local function bind(bufnr)
    ---@type {lhs: string, desc: string, fn: fun()}[]
    local actions = {
        {
            lhs = "<CR>",
            desc = "Open this note's prose for writing",
            fn = function()
                local row = M.row_at(bufnr, vim.fn.line("."))
                local state = states[bufnr]
                if not row or not state then
                    return
                end
                local where = vim.tbl_extend("force", state.config.editor, { focus = true })
                editor.open(row.entry, where, state.config.filetype)
            end,
        },
        {
            lhs = "gf",
            desc = "Jump to the code this note is about",
            fn = function()
                visit(bufnr)
            end,
        },
        {
            lhs = "<Tab>",
            desc = "Jump to the next column",
            fn = function()
                step(bufnr, M.next_column)
            end,
        },
        {
            lhs = "<S-Tab>",
            desc = "Jump to the previous column",
            fn = function()
                step(bufnr, M.prev_column)
            end,
        },
        {
            -- Likely taken by oil in a source buffer, but free in here, and it
            -- means what it means there: go up
            lhs = "-",
            desc = "Widen to every annotation in the project",
            fn = function()
                local state = states[bufnr]
                if not state or state.scope == "project" then
                    return
                end
                -- The filter travels with you: widening a listing of orphans
                -- should show the project's orphans, not everything it holds
                local _, err = M.open_project(state.path, {
                    config = state.config,
                    filter = state.filter,
                })
                if err then
                    vim.notify("sidenote: " .. err, vim.log.levels.ERROR)
                end
            end,
        },
    }
    actions[#actions + 1] = {
        lhs = "?",
        desc = "Show this help",
        fn = function()
            help(actions)
        end,
    }

    for _, action in ipairs(actions) do
        vim.keymap.set("n", action.lhs, action.fn, {
            buffer = bufnr,
            desc = action.desc,
            nowait = true,
        })
    end
end

---Name a listing after what it covers.
---
---Absolute, so two projects open at once cannot collide on one relative path;
---a trailing slash marks a project listing, the way a directory reads.
---@param state sidenote.browser.State
---@return string
local function name_for(state)
    if state.scope == "project" then
        return M.SCHEME .. state.path .. "/"
    end
    return M.SCHEME .. state.path
end

---Show a listing in the current window, reusing its buffer if one exists.
---
---A filter is not part of the name, so re-opening the same listing with a
---different one narrows the view you already have rather than making a second.
---@param state sidenote.browser.State
---@return integer bufnr
local function show(state)
    local name = name_for(state)
    local bufnr = existing(name)
    if not bufnr then
        bufnr = vim.api.nvim_create_buf(true, false)
        vim.bo[bufnr].buftype = "acwrite"
        vim.bo[bufnr].swapfile = false
        vim.api.nvim_buf_set_name(bufnr, name)
        vim.api.nvim_create_autocmd("BufWipeout", {
            buffer = bufnr,
            once = true,
            desc = "Drop the browser's diff baseline along with its buffer",
            callback = function()
                states[bufnr] = nil
            end,
        })
        vim.api.nvim_create_autocmd("BufWriteCmd", {
            buffer = bufnr,
            desc = "Confirm and apply the edits made to this listing",
            callback = function()
                report(M.write(bufnr))
            end,
        })
        bind(bufnr)
    end

    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.bo[bufnr].filetype = "sidenote"
    configure(winid)

    paint(bufnr, state)
    return bufnr
end

---@class sidenote.browser.OpenOpts
---@field config? sidenote.Config resolved configuration, read from vim.g when omitted
---@field filter? sidenote.browser.Filter which annotations survive into the listing

---Open the listing for one source buffer, in the current window.
---
---From inside a file's listing this goes back to the file instead, so one
---mapping toggles between the two. A project listing has no single file to
---return to and says so.
---@param source integer
---@param opts? sidenote.browser.OpenOpts
---@return integer|nil bufnr the listing, or the listed file when toggling back
---@return string|nil err
function M.open(source, opts)
    opts = opts or {}
    local cfg = opts.config or config.get()

    local state = states[source]
    if state then
        if state.scope ~= "file" then
            return nil, "this lists the whole project; gf jumps to a note's code"
        end
        vim.cmd.edit(vim.fn.fnameescape(state.path))
        return vim.api.nvim_get_current_buf(), nil
    end

    local target, target_err = buffer.target(source, { scope = "file" })
    if not target then
        return nil, target_err
    end
    local _, roots_err = strategy.resolve(target.path, cfg)
    if roots_err then
        return nil, roots_err
    end

    return show({
        scope = "file",
        path = target.path,
        source = source,
        config = cfg,
        filter = opts.filter or {},
        rows = {},
    })
end

---Open the listing for a whole project, in the current window.
---
---`path` may be any file inside the project; the root is found from it the same
---way the store's is.
---@param path string
---@param opts? sidenote.browser.OpenOpts
---@return integer|nil bufnr
---@return string|nil err
function M.open_project(path, opts)
    opts = opts or {}
    local cfg = opts.config or config.get()

    local resolved = vim.uv.fs_realpath(path) or path
    local root = project.root(resolved)
    if not root then
        return nil,
            ("no project root at or above %s; expected one of %s"):format(
                resolved,
                table.concat(project.MARKERS, ", ")
            )
    end

    return show({
        scope = "project",
        path = root,
        source = nil,
        config = cfg,
        filter = opts.filter or {},
        rows = {},
    })
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

---The annotation a buffer line belongs to, header or prose alike.
---@param bufnr integer
---@param lnum integer 1-based
---@return sidenote.browser.Row|nil
function M.row_at(bufnr, lnum)
    local state = states[bufnr]
    if not state then
        return nil
    end
    for n = lnum, 1, -1 do
        local text = vim.api.nvim_buf_get_lines(bufnr, n - 1, n, false)[1] or ""
        local id = text:match("^/(%S+) ")
        if id then
            for _, row in ipairs(state.rows) do
                if row.entry.id == id then
                    return row
                end
            end
            return nil
        end
    end
    return nil
end

---Byte column each field of a header line starts at, in written order.
---@param text string
---@return integer[]
local function column_starts(text)
    local row = parse.header(text)
    if not row then
        return {}
    end
    local starts = {}
    for i, column in ipairs(render.COLUMNS) do
        starts[i] = row.fields[column.name].first
    end
    return starts
end

---Where `<Tab>` should land from byte column `col`, or nil at the last column.
---@param text string
---@param col integer 1-based byte column
---@return integer|nil
function M.next_column(text, col)
    for _, start in ipairs(column_starts(text)) do
        if start > col then
            return start
        end
    end
    return nil
end

---Where `<S-Tab>` should land from byte column `col`, or nil at the first.
---@param text string
---@param col integer 1-based byte column
---@return integer|nil
function M.prev_column(text, col)
    local previous = nil
    for _, start in ipairs(column_starts(text)) do
        if start >= col then
            return previous
        end
        previous = start
    end
    return previous
end

---@class sidenote.browser.WriteOpts
---@field confirm? sidenote.browser.ConfirmFn asks before anything is applied, defaulting to the dialog

---@param problems sidenote.browser.ParseError[]
---@return string[]
local function reported(problems)
    local out = {}
    for i, problem in ipairs(problems) do
        out[i] = ("line %d: %s"):format(problem.lnum, problem.message)
    end
    return out
end

---Apply what the buffer now says, after asking.
---
---Parsing and validation both run before the dialog, so it can never offer an
---action that would fail. A refusal leaves the buffer exactly as it is, ready
---to be corrected and written again.
---@param bufnr integer
---@param opts? sidenote.browser.WriteOpts
---@return integer applied
---@return string[] problems
function M.write(bufnr, opts)
    local state = states[bufnr]
    if not state then
        return 0, { "not a sidenote browser" }
    end

    -- Checked before anything is parsed: a row whose own location cannot be
    -- read back would otherwise diff as a move to a truncated path
    local unreadable = {}
    for i, row in ipairs(state.rows) do
        if render.ambiguous(row) then
            local complaint = "%s holds consecutive spaces, which a listing cannot tell from a"
                .. " column boundary; edit this annotation from the source buffer"
            unreadable[#unreadable + 1] = {
                lnum = i,
                message = complaint:format(row.entry.record.path),
            }
        end
    end
    if #unreadable > 0 then
        return 0, reported(unreadable)
    end

    local rows, errors = parse.buffer(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    if #errors > 0 then
        return 0, reported(errors)
    end

    local actions = diff.compute(state, rows)
    if #actions == 0 then
        vim.bo[bufnr].modified = false
        return 0, {}
    end

    local impossible = apply.validate(actions, state)
    if #impossible > 0 then
        return 0, reported(impossible)
    end

    local ask = opts and opts.confirm or confirm.ask
    if not ask(actions) then
        return 0, {}
    end

    local applied, failures = apply.run(actions, state)
    M.rerender(bufnr)
    return applied, failures
end

return M
