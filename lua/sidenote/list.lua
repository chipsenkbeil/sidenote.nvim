local config = require("sidenote.config")
local cycle = require("sidenote.cycle")
local filter = require("sidenote.filter")
local project = require("sidenote.store.project")
local store = require("sidenote.store")

---Annotations as quickfix and location lists.
---
---The vim-native way to sweep a set of notes: populate, open, jump with
---the machinery every other tool already feeds. Sidenote-titled lists
---carry verbs of their own — cycle, open, delete — each item holding its
---identity in `user_data`, so the keys survive any reordering.
---@class sidenote.list
local M = {}

---The resolved options behind the last list of each shape, for rebuilds.
---@type table<"loclist"|"qflist", sidenote.list.Opts>
local held = {}

---One list line: bracketed metadata, the summary, and a hurt status.
---
---The bracket always holds kind, state and pen in that order — `-` for no
---pen — because the verbs read which field the cursor sits on from it.
---@param entry sidenote.session.Entry
---@return string
local function label(entry)
    local rec = entry.record
    local parts = { rec.kind, rec.state, rec.pen or "-" }
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

---The items a list of `opts`'s scope holds, and the opts made rebuildable.
---@param opts sidenote.list.Opts
---@param cfg sidenote.Config
---@return table[] items
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
---@return table|nil items every item the list holds
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
---@return table|nil item the quickfix item itself
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
---@param item {bufnr?: integer} quickfix item as `getqflist` returns it
---@return integer|nil
local function loaded_source(item)
    if item.bufnr and item.bufnr > 0 and vim.api.nvim_buf_is_loaded(item.bufnr) then
        return item.bufnr
    end
    return nil
end

---Which field the cursor sits on, read from the rendered line's bracket.
---
---The same idiom as the browser's `t`: the word under the cursor decides,
---and anywhere else on the line means state. Read from the rendered text
---rather than the item, so it survives a custom 'quickfixtextfunc' as long
---as the bracket does.
---@return "kind"|"state"|"pen"
local function field_under_cursor()
    local line = vim.api.nvim_get_current_line()
    local col = vim.fn.col(".")
    local bopen, bclose = line:find("%[[^%]]*%]")
    if not bopen or col <= bopen or col >= bclose then
        return "state"
    end

    local order = { "kind", "state", "pen" }
    local index = 0
    for start, word in line:sub(bopen + 1, bclose - 1):gmatch("()(%S+)") do
        index = index + 1
        local first = bopen + start
        if col >= first and col < first + #word then
            return order[index] or "state"
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

---Values each interactive filter key offers, as in the browser.
local FILTERS = {
    kind = require("sidenote.core.record").KIND_NAMES,
    state = require("sidenote.core.record").STATE_NAMES,
    status = require("sidenote.core.resolve").STATUS_NAMES,
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
        -- Narrowing needs a file; the one under the cursor is the obvious
        -- candidate, and the one the list opened from is the fallback
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

---Bind the verbs into a quickfix buffer, guarded per keypress.
---
---One qf buffer serves every list a session ever shows, so the keys decide
---at press time: in a sidenote-titled list they act, anywhere else they
---fall through to whatever the key normally does.
---@param bufnr integer quickfix buffer
function M.bind(bufnr)
    ---@param lhs string
    ---@param verb fun()
    local function on(lhs, verb)
        vim.keymap.set("n", lhs, function()
            if not ours() then
                return lhs
            end
            -- Scheduled: an expression mapping may not edit anything itself
            vim.schedule(verb)
            return ""
        end, { buffer = bufnr, expr = true, nowait = true })
    end

    on("t", function()
        turn(1)
    end)
    on("T", function()
        turn(-1)
    end)
    on("o", open_note)
    on("d", delete_note)
    on("s", flip_scope)
    on("fk", function()
        refilter("kind")
    end)
    on("fs", function()
        refilter("state")
    end)
    on("fa", function()
        refilter("status")
    end)
    on("ff", function()
        refilter("path")
    end)
    on("fc", function()
        refilter(nil)
    end)
end

return M
