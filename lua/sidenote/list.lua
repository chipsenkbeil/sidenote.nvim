local config = require("sidenote.config")
local cycle = require("sidenote.cycle")
local filter = require("sidenote.filter")
local highlight = require("sidenote.highlight")
local project = require("sidenote.store.project")
local record = require("sidenote.core.record")
local resolve = require("sidenote.core.resolve")
local store = require("sidenote.store")

---Annotations as quickfix and location lists.
---
---The vim-native way to sweep a set of notes: populate, open, jump with
---the machinery every other tool already feeds. Sidenote-titled lists
---carry verbs of their own — cycle, open, delete.
---@class sidenote.list
local M = {}

---The bracketed fields, in the order they render and the cursor reads them back.
local FIELDS = { "kind", "state", "pen" }

---What a note with no pen shows in the pen column.
local NO_PEN = "-"

---The resolved options behind the last list of each shape, for rebuilds.
---@type table<"loclist"|"qflist", sidenote.list.Opts>
local held = {}

---One list line: bracketed metadata, the summary, and a hurt status.
---@param entry sidenote.session.Entry
---@return string
local function label(entry)
    local parts = {}
    for i, field in ipairs(FIELDS) do
        parts[i] = entry.record[field] or NO_PEN
    end
    local text = "[" .. table.concat(parts, " ") .. "]"
    if entry.summary then
        text = text .. " " .. entry.summary
    end
    if entry.status ~= "attached" then
        text = text .. " (" .. entry.status .. ")"
    end
    return text
end

---@class sidenote.list.Opts
---@field filter? sidenote.Filter which annotations make the list
---@field scope? "file"|"project" how wide a set; each list has its default
---@field bufnr? integer buffer a file-scoped list covers, defaulting to current
---@field path? string any file inside the project a project-scoped list covers

---One line of a list: where the note is, what it reads as, and which note it is.
---@class sidenote.list.Item
---@field bufnr? integer buffer the annotated file is loaded in
---@field filename? string path to the annotated file, for an item with no buffer
---@field lnum integer line the note anchors to, 1 when it has no position
---@field col integer column the note anchors to
---@field text string the rendered line
---@field user_data {sidenote: {id: string, root: string}} identity, surviving any reordering

---The items a list of `opts`'s scope holds.
---
---Fills in the buffer or path the scope resolved to, so a rebuild from the
---same opts lists the same set.
---@param opts sidenote.list.Opts
---@param cfg sidenote.Config
---@return sidenote.list.Item[] items
local function items_for(opts, cfg)
    local items = {}
    if opts.scope == "project" then
        local from = opts.path
        if not from or from == "" then
            from = vim.api.nvim_buf_get_name(opts.bufnr or vim.api.nvim_get_current_buf())
        end
        if from == "" then
            from = vim.fn.getcwd()
        end
        opts.path = from
        local root = project.root(from)
        local entries = require("sidenote.scan").project({ path = from, config = cfg })
        for _, entry in ipairs(filter.narrow(entries, opts.filter)) do
            local rec = entry.record
            local path = rec.path:sub(1, 1) == "/" and rec.path
                or (root and (root .. "/" .. rec.path) or rec.path)
            items[#items + 1] = {
                filename = path,
                lnum = entry.line_start or rec.line_start or 1,
                col = entry.col_start or 1,
                text = label(entry),
                user_data = { sidenote = { id = entry.id, root = entry.root } },
            }
        end
        return items
    end

    local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
    opts.bufnr = bufnr
    local entries = require("sidenote.session").entries(bufnr, cfg)
    for _, entry in ipairs(filter.narrow(entries, opts.filter)) do
        items[#items + 1] = {
            bufnr = bufnr,
            lnum = entry.line_start or entry.record.line_start or 1,
            col = entry.col_start or 1,
            text = label(entry),
            user_data = { sidenote = { id = entry.id, root = entry.root } },
        }
    end
    return items
end

---Fill the current window's location list, with this buffer's annotations
---by default; `scope = "project"` widens it to the whole project's.
---@param opts? sidenote.list.Opts
---@return integer listed
function M.loclist(opts)
    opts = opts or {}
    opts.scope = opts.scope or "file"
    local items = items_for(opts, config.get())
    held.loclist = opts

    vim.fn.setloclist(0, {}, " ", { title = "sidenote", items = items })
    if #items > 0 then
        vim.cmd.lopen()
    else
        vim.notify("sidenote: no annotations match", vim.log.levels.INFO)
    end
    return #items
end

---Fill the quickfix list, with the whole project's annotations by default;
---`scope = "file"` narrows it to this buffer's.
---@param opts? sidenote.list.Opts
---@return integer listed
function M.qflist(opts)
    opts = opts or {}
    opts.scope = opts.scope or "project"
    local items = items_for(opts, config.get())
    held.qflist = opts

    vim.fn.setqflist({}, " ", { title = "sidenote", items = items })
    if #items > 0 then
        vim.cmd.copen()
    else
        vim.notify("sidenote: no annotations match", vim.log.levels.INFO)
    end
    return #items
end

---Which sidenote list the current window shows, if it shows one at all.
---@return "loclist"|"qflist"|nil shape
---@return sidenote.list.Item[]|nil items every item the list holds
local function ours()
    local win = vim.api.nvim_get_current_win()
    local info = vim.fn.getwininfo(win)[1]
    if not info or info.quickfix ~= 1 then
        return nil, nil
    end
    local shape = info.loclist == 1 and "loclist" or "qflist"
    local list = shape == "loclist" and vim.fn.getloclist(win, { title = 0, items = 0 })
        or vim.fn.getqflist({ title = 0, items = 0 })
    if list.title ~= "sidenote" then
        return nil, nil
    end
    return shape, list.items
end

---What the cursor sits on when the current window shows a sidenote list.
---@return {id: string, root: string}|nil payload
---@return sidenote.list.Item|nil item the item itself
---@return "loclist"|"qflist"|nil shape
local function under_cursor()
    local shape, items = ours()
    if not shape then
        return nil, nil, nil
    end
    local item = items[vim.fn.line(".")]
    local payload = item and item.user_data and item.user_data.sidenote
    return payload, item, shape
end

---Re-run the list the verbs just changed, holding the cursor still.
---
---Column included: cycling a pen means pressing `t` on the pen word again
---and again, which only works if the cursor is still on it.
---@param shape "loclist"|"qflist"
local function rebuild(shape)
    local line, col = vim.fn.line("."), vim.fn.col(".")
    if shape == "loclist" then
        M.loclist(held.loclist)
    else
        M.qflist(held.qflist)
    end
    pcall(vim.fn.cursor, line, col)
end

---The buffer an item's annotated file is loaded in, for repaints.
---@param item sidenote.list.Item
---@return integer|nil
local function loaded_source(item)
    if item.bufnr and item.bufnr > 0 and vim.api.nvim_buf_is_loaded(item.bufnr) then
        return item.bufnr
    end
    return nil
end

---Which field the cursor sits on, read from the rendered line's bracket.
---
---The word under the cursor decides, and anywhere else on the line means
---state. Reading the rendered text rather than the item survives a custom
---'quickfixtextfunc', as long as the bracket does.
---@return "kind"|"state"|"pen"
local function field_under_cursor()
    local line = vim.api.nvim_get_current_line()
    local col = vim.fn.col(".")
    local bopen, bclose = line:find("%[[^%]]*%]")
    if not bopen or col <= bopen or col >= bclose then
        return "state"
    end

    local index = 0
    for start, word in line:sub(bopen + 1, bclose - 1):gmatch("()(%S+)") do
        index = index + 1
        local first = bopen + start
        if col >= first and col < first + #word then
            return FIELDS[index] or "state"
        end
    end
    return "state"
end

---Rotate the field under the cursor and redraw the list.
---@param offset integer 1 forward, -1 backward
local function turn(offset)
    local payload, item, shape = under_cursor()
    if not payload or not item or not shape then
        return
    end
    local field = field_under_cursor()
    local cfg = config.get()
    local rec = store.read(payload.root, payload.id)
    if not rec then
        return
    end
    local turned = cycle.turn(rec, { field = field, offset = offset, config = cfg })
    local wrote = cycle.set(payload, {
        field = field,
        value = rec[field],
        config = cfg,
        bufnr = loaded_source(item),
    })
    if wrote then
        vim.notify(("sidenote: %s %s"):format(field, turned))
        rebuild(shape)
    end
end

---Open the item's prose in the editor, focused.
local function open_note()
    local payload, item = under_cursor()
    if not payload then
        return
    end
    local cfg = config.get()
    local rec = store.read(payload.root, payload.id)
    local note = {
        root = payload.root,
        id = payload.id,
        record = rec,
        line_start = rec and rec.line_start,
        line_end = rec and rec.line_end,
        source = item and loaded_source(item),
        config = cfg,
    }
    local editor = vim.tbl_extend("force", cfg.editor, { focus = true })
    require("sidenote.editor").open(note, editor, cfg.filetype)
end

---Delete the item under the cursor, after a confirmation that quotes it.
local function delete_note()
    local payload, item, shape = under_cursor()
    if not payload or not shape then
        return
    end
    local cfg = config.get()
    local summary = store.summary(payload.root, payload.id, cfg.filetype)
    local asked = ('sidenote: delete "%s"?'):format(summary or "no prose")
    if vim.fn.confirm(asked, "&Delete\n&Cancel", 2) ~= 1 then
        return
    end
    store.delete(payload.root, payload.id, cfg.filetype)
    local source = item and loaded_source(item)
    if source then
        require("sidenote.session").refresh(source, cfg)
    end
    rebuild(shape)
end

---Values each interactive filter key offers.
local FILTERS = {
    kind = record.KIND_NAMES,
    state = record.STATE_NAMES,
    status = resolve.STATUS_NAMES,
}

---Change one filter key and rebuild the list through it.
---@param key "kind"|"state"|"status"|"path"|nil nil clears every filter
local function refilter(key)
    local shape = ours()
    if not shape then
        return
    end
    local opts = held[shape]
    opts.filter = opts.filter or {}

    if key == nil then
        opts.filter = {}
        rebuild(shape)
    elseif key == "path" then
        vim.ui.input({ prompt = "sidenote path contains: " }, function(answer)
            if answer ~= nil then
                opts.filter.path = answer ~= "" and answer or nil
                rebuild(shape)
            end
        end)
    else
        local choices = { "(all)" }
        vim.list_extend(choices, FILTERS[key])
        vim.ui.select(choices, { prompt = "sidenote " .. key }, function(choice)
            if choice then
                opts.filter[key] = choice ~= "(all)" and choice or nil
                rebuild(shape)
            end
        end)
    end
end

---Flip the list between this buffer's notes and the whole project's.
local function flip_scope()
    local shape, items = ours()
    if not shape then
        return
    end
    local opts = held[shape]
    if opts.scope == "project" then
        local item = items[vim.fn.line(".")]
        local bufnr = item and loaded_source(item) or opts.bufnr
        if not bufnr then
            vim.notify("sidenote: no file here to narrow to", vim.log.levels.WARN)
            return
        end
        opts.scope, opts.bufnr = "file", bufnr
    else
        opts.scope = "project"
    end
    rebuild(shape)
    vim.notify("sidenote: " .. opts.scope .. " scope")
end

---What `g?` shows below the mappings themselves.
local HELP_FOOTER = {
    "",
    "  Only a sidenote-titled list answers these keys",
    "  The rest is stock quickfix: <CR> jumps, :cnext walks",
}

---The verbs a sidenote-titled list answers, kept as data first.
---
---One list serves twice — the keymaps are built from it and `g?` renders it —
---so the help can never drift from what the keys do.
---@return {lhs: string, desc: string, fn: fun()}[]
local function verbs()
    ---@type {lhs: string, desc: string, fn: fun()}[]
    local actions = {
        {
            lhs = "t",
            desc = "Cycle state forward; kind or pen on their words",
            fn = function()
                turn(1)
            end,
        },
        {
            lhs = "T",
            desc = "Cycle state backward; kind or pen on their words",
            fn = function()
                turn(-1)
            end,
        },
        {
            lhs = "o",
            desc = "Open this note's prose for writing",
            fn = open_note,
        },
        {
            lhs = "d",
            desc = "Delete this note, after confirming",
            fn = delete_note,
        },
        {
            lhs = "s",
            desc = "Flip between file and project scope",
            fn = flip_scope,
        },
        {
            lhs = "fk",
            desc = "Filter by kind",
            fn = function()
                refilter("kind")
            end,
        },
        {
            lhs = "fs",
            desc = "Filter by state",
            fn = function()
                refilter("state")
            end,
        },
        {
            lhs = "fa",
            desc = "Filter by anchor status",
            fn = function()
                refilter("status")
            end,
        },
        {
            lhs = "ff",
            desc = "Filter by path substring",
            fn = function()
                refilter("path")
            end,
        },
        {
            lhs = "fc",
            desc = "Clear every filter",
            fn = function()
                refilter(nil)
            end,
        },
    }
    actions[#actions + 1] = {
        lhs = "g?",
        desc = "Show this help",
        fn = function()
            require("sidenote.help").show(actions, { footer = HELP_FOOTER })
        end,
    }
    return actions
end

---What the winbar names, in the order it names them.
---
---A reminder, not the help: the filters collapse into one `f` and the rest is
---behind `g?`. `<CR>` is stock quickfix and leads because it is what a reader
---reaches for first. A test holds every other key here to a real verb.
---@type {lhs: string, label: string}[]
local BAR = {
    { lhs = "<CR>", label = "jump" },
    { lhs = "t", label = "cycle" },
    { lhs = "o", label = "open" },
    { lhs = "d", label = "delete" },
    { lhs = "s", label = "scope" },
    { lhs = "f", label = "filter" },
    { lhs = "g?", label = "help" },
}

---The winbar a sidenote list wears, naming what its keys do.
---@return string winbar statusline-format text
function M.winbar()
    local bar = "%#" .. highlight.WINBAR .. "#"
    local key = "%#" .. highlight.BARE .. "#"
    local parts = {}
    for _, item in ipairs(BAR) do
        parts[#parts + 1] = ("%s  %s%s%s %s"):format(
            bar,
            key,
            item.lhs:gsub("%%", "%%%%"),
            bar,
            item.label
        )
    end
    return table.concat(parts) .. bar
end

---@param bufnr integer
---@return integer[] winids every window showing the buffer
local function windows_of(bufnr)
    local out = {}
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(winid) == bufnr then
            out[#out + 1] = winid
        end
    end
    return out
end

---Put the winbar up, or take down only the one this put there.
---@param bufnr integer
---@param wanted string the winbar to show, empty to take ours down
local function dress(bufnr, wanted)
    local ours_now = M.winbar()
    for _, winid in ipairs(windows_of(bufnr)) do
        local showing = vim.api.nvim_get_option_value("winbar", { win = winid, scope = "local" })
        -- Another tool's winbar is its own; only ever replace one of ours
        if showing == "" or showing == ours_now then
            vim.api.nvim_set_option_value("winbar", wanted, { win = winid, scope = "local" })
        end
    end
end

---Answer the verbs in a sidenote-titled list, and leave every other list alone.
---
---One quickfix buffer serves every list a session shows, so this runs again
---whenever the window is entered, adding the verbs to our own list and taking
---them back out of anyone else's. A buffer-local mapping is singular: merely
---deciding at press time would still have claimed the key from whatever tool
---filled the list this time, and left that tool's own `d` unreachable.
---@param bufnr integer quickfix buffer
function M.bind(bufnr)
    if not ours() then
        M.unbind(bufnr)
        return
    end
    for _, action in ipairs(verbs()) do
        vim.keymap.set("n", action.lhs, action.fn, {
            buffer = bufnr,
            desc = action.desc,
            nowait = true,
        })
    end
    dress(bufnr, M.winbar())
end

---Take the verbs back out, so the list's own tool answers its keys again.
---@param bufnr integer quickfix buffer
function M.unbind(bufnr)
    for _, action in ipairs(verbs()) do
        pcall(vim.keymap.del, "n", action.lhs, { buffer = bufnr })
    end
    dress(bufnr, "")
end

return M
