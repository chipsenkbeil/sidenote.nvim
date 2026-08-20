local apply = require("sidenote.browser.apply")
local buffer = require("sidenote.buffer")
local capture = require("sidenote.capture")
local config = require("sidenote.config")
local confirm = require("sidenote.browser.confirm")
local diff = require("sidenote.browser.diff")
local editor = require("sidenote.editor")
local hash = require("sidenote.core.hash")
-- `sidenote.render` paints status indicators, which is what it is doing here;
-- the browser's own renderer already owns the name
local indicator = require("sidenote.render")
local location = require("sidenote.location")
local parse = require("sidenote.browser.parse")
local project = require("sidenote.store.project")
local record = require("sidenote.core.record")
local render = require("sidenote.browser.render")
local scan = require("sidenote.scan")
local session = require("sidenote.session")
local store = require("sidenote.store")
local strategy = require("sidenote.store.strategy")
local window = require("sidenote.window")

---@alias sidenote.browser.Filter sidenote.Filter

---@class sidenote.browser.State
---@field scope "file"|"project" how wide a set the listing covers
---@field path string absolute path of the source file, or of the project root
---@field source integer|nil buffer the annotations came from, absent for a project
---@field config sidenote.Config configuration the browser was opened with
---@field filter sidenote.browser.Filter which annotations survive into the listing
---@field rows sidenote.browser.Row[] what was rendered, in buffer order
---@field headers integer[] buffer line of each row's header, in row order
---@field lines string[] exactly what was rendered, the clean baseline
---@field tick integer buffer tick at that render, the dirty check's fast path

---An oil-style editable listing of one file's annotations.
---@class sidenote.browser
local M = {}

---Prefix naming a browser buffer, followed by the absolute source path.
M.SCHEME = "sidenote://"

---Fold expression making each annotation one fold, opened by its header.
---
---Structure is read back out of the text, so nothing has to be kept in step
---with the buffer as it is edited. The marker is matched fully, so a prose
---line mentioning /etc/hosts does not start a fold of its own.
M.FOLDEXPR = [[getline(v:lnum) =~ '^/\w\+ ' ? '>1' : '1']]

---@type table<integer, sidenote.browser.State>
local states = {}

---Whether a listing holds edits `:w` has not applied.
---
---By content, not by the modified flag: the flag is kept permanently off so
---abandoning a listing never complains, and an undo back to the rendered
---text counts as clean again.
---@param bufnr integer
---@return boolean
local function dirty(bufnr)
    local state = states[bufnr]
    if not state or state.tick == vim.api.nvim_buf_get_changedtick(bufnr) then
        return false
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if #lines ~= #state.lines then
        return true
    end
    for i, line in ipairs(lines) do
        if line ~= state.lines[i] then
            return true
        end
    end
    return false
end

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

local survives = require("sidenote.filter").survives

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
    -- A closed fold renders as its header's columns plus a summary preview,
    -- assembled as highlighted chunks; see M.foldtext
    set_local(winid, "foldtext", "v:lua.require'sidenote.browser'.foldtext()")
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

---Most of a summary a closed fold will preview before cutting off.
local PREVIEW_MAX = 80

---Render a closed row: its header's columns plus a preview of its summary.
---
---Built from the buffer lines, never from rendered state, so an edit made
---while the fold was open shows through the moment it closes. Display only:
---the preview may truncate, because nothing here can leak into a write.
---@return {[1]: string, [2]: string}[] chunks
function M.foldtext()
    local start = vim.v.foldstart
    local header = vim.fn.getline(start)
    local row = parse.header(header)
    if not row then
        return { { header, "Normal" } }
    end

    -- The header's own text, sliced by field so each column keeps its color;
    -- the concealed id is simply not emitted
    local groups = {
        kind = "sidenoteKind",
        state = "sidenoteState",
        pen = "sidenotePen",
        location = "sidenoteLocation",
    }
    local chunks = {}
    local cursor = row.fields.kind.first
    for _, name in ipairs({ "kind", "state", "pen", "location" }) do
        local field = row.fields[name]
        if field.first > cursor then
            chunks[#chunks + 1] = { header:sub(cursor, field.first - 1), "Normal" }
        end
        chunks[#chunks + 1] = { header:sub(field.first, field.last), groups[name] }
        cursor = field.last + 1
    end

    local summary = start < vim.v.foldend and vim.trim(vim.fn.getline(start + 1)) or ""
    if summary ~= "" then
        if #summary > PREVIEW_MAX then
            summary = summary:sub(1, PREVIEW_MAX) .. "…"
        end
        chunks[#chunks + 1] = { "  ", "Normal" }
        chunks[#chunks + 1] = { summary, "sidenoteProse" }
    end
    return chunks
end

---Collapse every annotation, then hand back the rows that were open.
---
---A fold created after 'foldlevel' was last set opens regardless of it, so
---this runs once the lines are in place rather than alongside the other
---window options. Re-opening by id is what lets a repaint hold still: a
---cycle rewrites the listing, but the fold you were working in stays open.
---@param bufnr integer
---@param state sidenote.browser.State
---@param keep table<string, boolean>|nil ids whose rows stay open
local function refold(bufnr, state, keep)
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(winid) == bufnr then
            set_local(winid, "foldlevel", 0)
            if keep then
                vim.api.nvim_win_call(winid, function()
                    for i, row in ipairs(state.rows) do
                        if keep[row.entry.id] then
                            pcall(vim.cmd, state.headers[i] .. "foldopen")
                        end
                    end
                end)
            end
        end
    end
end

---Which rows are open right now, by id, for a repaint to hand back.
---
---Read from the current window, which is where every caller of a
---preserving repaint already sits.
---@param state sidenote.browser.State
---@return table<string, boolean>
local function unfolded(state)
    local open = {}
    for i, row in ipairs(state.rows or {}) do
        local lnum = state.headers and state.headers[i]
        if lnum and vim.fn.foldclosed(lnum) == -1 then
            open[row.entry.id] = true
        end
    end
    return open
end

---@param bufnr integer
---@param state sidenote.browser.State
---@param keep table<string, boolean>|nil ids whose folds a repaint keeps open
local function paint(bufnr, state, keep)
    state.rows = rows_for(state)
    local lines, headers = render.rows(state.rows)

    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modified = false
    state.lines = lines
    state.headers = headers
    state.tick = vim.api.nvim_buf_get_changedtick(bufnr)
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
    -- Never the range overlay: the listing is text about notes, not the
    -- annotated code, so pen and status ink belong to the source alone
    indicator.paint(bufnr, marks, { style = "sign", highlight = "never" })
    refold(bufnr, state, keep)
end

---Repaint the loaded buffer of every file a listing edit touched.
---
---The edit changed records out from under any window showing the annotated
---code, so its marks follow now rather than at that buffer's next save.
---@param state sidenote.browser.State
---@param paths string[] project-relative or absolute paths whose buffers repaint
local function repaint_sources(state, paths)
    local root = project.root(state.path)
    local seen = {}
    for _, given in ipairs(paths) do
        local path = given:sub(1, 1) == "/" and given or (root and (root .. "/" .. given) or given)
        local wanted = vim.uv.fs_realpath(path) or path
        if not seen[wanted] then
            seen[wanted] = true
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(buf) and not states[buf] then
                    local name = vim.api.nvim_buf_get_name(buf)
                    if (vim.uv.fs_realpath(name) or name) == wanted then
                        session.refresh(buf, state.config)
                    end
                end
            end
        end
    end
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

---Toggle the fold under the cursor, the way org's TAB cycles a headline.
local function toggle_fold()
    pcall(vim.cmd, "normal! za")
end

---Toggle every fold at once: overview when anything is open, else all open.
---
---Org's shift-TAB, translated: one key flips between the index and the
---full text, and which way it flips is read from the screen, not counted.
---@param state sidenote.browser.State
local function toggle_all(state)
    for _, lnum in ipairs(state.headers or {}) do
        if vim.fn.foldclosed(lnum) == -1 then
            vim.cmd("normal! zM")
            return
        end
    end
    vim.cmd("normal! zR")
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

---Which field a cycle at the cursor means: kind or pen on their own columns,
---and state everywhere else on the row.
---@param bufnr integer
---@return "kind"|"state"|"pen"
local function cycle_target(bufnr)
    local lnum, col = unpack(vim.api.nvim_win_get_cursor(0))
    local text = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
    local row = parse.header(text)
    if not row then
        return "state"
    end
    for _, name in ipairs({ "kind", "pen" }) do
        local field = row.fields[name]
        if col + 1 >= field.first and col + 1 <= field.last then
            return name
        end
    end
    return "state"
end

---Rotate a row's `kind`, `state` or `pen` in place, the way org rotates a
---headline.
---
---One pair of keys serves all three: the column under the cursor decides, and
---state is the default everywhere else on the row. One deliberate keystroke
---is its own confirmation, so the record is written directly and the listing
---repainted; the batched `:w` dialog is for text edits. A listing holding
---unsaved edits is left alone: repainting it would eat them.
---@param bufnr integer
---@param offset integer 1 forward, -1 backward
local function cycle(bufnr, offset)
    local row = M.row_at(bufnr, vim.fn.line("."))
    local state = states[bufnr]
    if not row or not state then
        return
    end
    local field = cycle_target(bufnr)
    if dirty(bufnr) then
        vim.notify("sidenote: apply or discard your edits first (:w)", vim.log.levels.WARN)
        return
    end

    local rec = store.read(row.entry.root, row.entry.id)
    if not rec then
        return
    end
    require("sidenote.cycle").turn(rec, { field = field, offset = offset, config = state.config })

    local ok, err = store.update(row.entry.root, rec)
    if not ok then
        vim.notify("sidenote: " .. tostring(err), vim.log.levels.ERROR)
        return
    end
    -- The repaint holds still: open folds stay open and the cursor stays
    -- put, so cycling reads as changing a word, not redrawing a screen
    local keep = unfolded(state)
    local cursor = vim.api.nvim_win_get_cursor(0)
    paint(bufnr, state, keep)
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
    repaint_sources(state, { row.entry.record.path })
end

---Values each interactive filter key offers.
local FILTERS = {
    kind = record.KIND_NAMES,
    state = record.STATE_NAMES,
    status = require("sidenote.core.resolve").STATUS_NAMES,
}

---Re-show the listing through a changed filter, keeping the cursor near.
---@param bufnr integer
---@param key string|nil nil resets every filter at once
---@param value string|nil nil widens the key back out
local function refilter(bufnr, key, value)
    local state = states[bufnr]
    if not state then
        return
    end
    if dirty(bufnr) then
        vim.notify("sidenote: apply or discard your edits first (:w)", vim.log.levels.WARN)
        return
    end
    if key then
        state.filter[key] = value
    else
        state.filter = {}
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    paint(bufnr, state)
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
end

---Offer one filter key's values, `(all)` first as the way back out.
---@param bufnr integer
---@param key "kind"|"state"|"status"
local function ask_filter(bufnr, key)
    local choices = { "(all)" }
    vim.list_extend(choices, FILTERS[key])
    vim.ui.select(choices, { prompt = "sidenote " .. key }, function(choice)
        if choice then
            refilter(bufnr, key, choice ~= "(all)" and choice or nil)
        end
    end)
end

---Create a file-wide note and open it for writing.
---
---A file listing already names its file; a project listing asks, suggesting
---the file of the row under the cursor. Typed creates left the grammar when
---the indentation did: a plain line is prose now, never an instruction.
---@param bufnr integer
local function create_note(bufnr)
    local state = states[bufnr]
    if not state then
        return
    end
    if dirty(bufnr) then
        vim.notify("sidenote: apply or discard your edits first (:w)", vim.log.levels.WARN)
        return
    end

    local path = state.path
    if state.scope == "project" then
        local row = M.row_at(bufnr, vim.fn.line("."))
        local answer = vim.fn.input("note on file: ", row and row.entry.record.path or "")
        if answer == "" then
            return
        end
        local root = project.root(state.path)
        path = answer:sub(1, 1) == "/" and answer or (root and (root .. "/" .. answer) or answer)
    end
    if vim.fn.filereadable(path) ~= 1 then
        vim.notify(("sidenote: %s does not exist"):format(path), vim.log.levels.WARN)
        return
    end

    local target = vim.fn.bufadd(path)
    vim.fn.bufload(target)
    local result, err = capture.run(target, { scope = "file", config = state.config })
    if not result then
        vim.notify("sidenote: " .. tostring(err), vim.log.levels.ERROR)
        return
    end
    paint(bufnr, state)
    local where = vim.tbl_extend("force", state.config.editor, { focus = true })
    editor.open({ root = result.root, id = result.id }, where, state.config.filetype)
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
                local note = vim.tbl_extend(
                    "keep",
                    { source = state.source, config = state.config },
                    row.entry
                )
                editor.open(note, where, state.config.filetype)
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
            lhs = "a",
            desc = "Create a note on a file, and open it",
            fn = function()
                create_note(bufnr)
            end,
        },
        {
            lhs = "t",
            desc = "Cycle state forward; kind or pen on their columns",
            fn = function()
                cycle(bufnr, 1)
            end,
        },
        {
            lhs = "T",
            desc = "Cycle state backward; kind or pen on their columns",
            fn = function()
                cycle(bufnr, -1)
            end,
        },
        {
            lhs = "fk",
            desc = "Filter by kind",
            fn = function()
                ask_filter(bufnr, "kind")
            end,
        },
        {
            lhs = "fs",
            desc = "Filter by state",
            fn = function()
                ask_filter(bufnr, "state")
            end,
        },
        {
            lhs = "fa",
            desc = "Filter by anchor status",
            fn = function()
                ask_filter(bufnr, "status")
            end,
        },
        {
            lhs = "ff",
            desc = "Filter by path substring",
            fn = function()
                local state = states[bufnr]
                local answer = vim.fn.input("path contains: ", state and state.filter.path or "")
                -- An empty answer widens back out
                refilter(bufnr, "path", answer ~= "" and answer or nil)
            end,
        },
        {
            lhs = "fc",
            desc = "Clear every filter",
            fn = function()
                refilter(bufnr, nil, nil)
            end,
        },
        {
            lhs = "<Tab>",
            desc = "Toggle this note's fold, org-style",
            fn = toggle_fold,
        },
        {
            lhs = "<S-Tab>",
            desc = "Toggle every fold: the index, or all the prose",
            fn = function()
                local state = states[bufnr]
                if state then
                    toggle_all(state)
                end
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
        -- The flag cannot be suppressed at the moment vim sets it, so it is
        -- swept back off after every edit and once more before a quit
        vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "QuitPre" }, {
            buffer = bufnr,
            desc = "A listing is a projection, so no edit of it ever needs saving",
            callback = function()
                vim.bo[bufnr].modified = false
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
---
---Folds a viewer had open stay open when the listing is on screen, so an
---applied `:w` reads as the edit landing, not as the view resetting.
---@param bufnr integer
---@return boolean rendered
function M.rerender(bufnr)
    local state = states[bufnr]
    if not state then
        return false
    end
    local keep = vim.api.nvim_get_current_buf() == bufnr and unfolded(state) or nil
    paint(bufnr, state, keep)
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

    local rows, errors = parse.buffer(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    if #errors > 0 then
        return 0, reported(errors)
    end

    -- A header pasted in from another listing names an id this baseline never
    -- rendered; nothing sound can be diffed for it
    local known = {}
    for _, row in ipairs(state.rows) do
        known[row.entry.id] = true
    end
    local foreign = {}
    for _, row in ipairs(rows) do
        if not known[row.id] then
            foreign[#foreign + 1] =
                { lnum = row.lnum, message = ("no annotation %s in this listing"):format(row.id) }
        end
    end
    if #foreign > 0 then
        return 0, reported(foreign)
    end

    local actions = diff.compute(state, rows)
    if #actions == 0 then
        -- The edit meant nothing once normalized; repaint to canonical form
        -- so the listing reads clean again
        M.rerender(bufnr)
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

    -- Gathered before the repaint replaces the rows: the files of every row
    -- acted on, plus each move's destination
    local acted = {}
    for _, action in ipairs(actions) do
        acted[action.id] = true
    end
    local touched = {}
    for _, row in ipairs(state.rows) do
        if acted[row.entry.id] then
            touched[#touched + 1] = row.entry.record.path
        end
    end
    for _, action in ipairs(actions) do
        local wanted = action.kind == "move" and location.parse(action.to) or nil
        if wanted then
            touched[#touched + 1] = wanted.path
        end
    end

    local applied, failures = apply.run(actions, state)
    M.rerender(bufnr)
    repaint_sources(state, touched)
    return applied, failures
end

return M
