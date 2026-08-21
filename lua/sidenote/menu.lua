local config = require("sidenote.config")
local cycle = require("sidenote.cycle")
local render = require("sidenote.browser.render")
local store = require("sidenote.store")

---An emacs-style menu for the note under the cursor.
---
---Every value the note could take, the current one marked; picking one
---writes it immediately and keeps the menu open, so kind, state and pen can
---all be set in one visit. Actions close it. Navigable with j/k and <CR>,
---with the single keys each action row names, or with the mouse.
---@class sidenote.menu
local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("sidenote.menu")

---@class sidenote.menu.Row
---@field text string what the row shows
---@field field? "kind"|"state"|"pen" which field a value row sets
---@field value? string what picking a value row writes, absent for no pen
---@field act? "open"|"view"|"delete"|"close" what an action row does

---@class sidenote.menu.State
---@field buf integer the menu's scratch buffer
---@field win integer the menu's float
---@field entry sidenote.session.Entry note the menu operates on
---@field cfg sidenote.Config configuration the menu was opened with
---@field rows sidenote.menu.Row[] what each buffer line means
---@field source integer annotated buffer the cursor sat in

---@type sidenote.menu.State|nil
local current

local RULE = { text = "  ────────────" }

---The rows the menu ends with; their keys are bound from the same table.
---@type {key: string, label: string, act: "open"|"view"|"delete"|"close"}[]
local ACTIONS = {
    { key = "o", label = "open the note", act = "open" },
    { key = "v", label = "view", act = "view" },
    { key = "d", label = "delete", act = "delete" },
    { key = "q", label = "close", act = "close" },
}

---@param entry sidenote.session.Entry
---@param cfg sidenote.Config
---@return sidenote.menu.Row[]
local function rows_for(entry, cfg)
    local rec = store.read(entry.root, entry.id) or entry.record
    local rows = {}

    ---@param field "kind"|"state"|"pen"
    local function values(field)
        for _, name in ipairs(cycle.ring(field, cfg)) do
            local held = rec[field] or render.NO_PEN
            rows[#rows + 1] = {
                text = ("  %s %s"):format(held == name and "●" or "○", name),
                field = field,
                value = name ~= render.NO_PEN and name or nil,
            }
        end
    end

    values("kind")
    rows[#rows + 1] = RULE
    values("state")
    rows[#rows + 1] = RULE
    values("pen")
    rows[#rows + 1] = RULE
    for _, action in ipairs(ACTIONS) do
        rows[#rows + 1] = {
            text = ("  %s  %s"):format(action.key, action.label),
            act = action.act,
        }
    end
    return rows
end

---Write the rows into the menu buffer, pen names in their own ink.
---@param buf integer
---@param rows sidenote.menu.Row[]
---@param cfg sidenote.Config
local function fill(buf, rows, cfg)
    local lines = {}
    for i, row in ipairs(rows) do
        lines[i] = row.text
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, NAMESPACE, 0, -1)
    for i, row in ipairs(rows) do
        if row.field == "pen" and row.value and cfg.pens[row.value] then
            local first = row.text:find(row.value, 1, true)
            if first then
                vim.api.nvim_buf_set_extmark(buf, NAMESPACE, i - 1, first - 1, {
                    end_col = #row.text,
                    hl_group = cfg.pens[row.value],
                })
            end
        elseif not row.field and not row.act then
            vim.api.nvim_buf_set_extmark(buf, NAMESPACE, i - 1, 0, {
                end_col = #row.text,
                hl_group = "NonText",
            })
        end
    end
end

---Dismiss the menu, if one is up.
function M.close()
    if current and vim.api.nvim_win_is_valid(current.win) then
        vim.api.nvim_win_close(current.win, true)
    end
    current = nil
end

---Write the value `row` stands for, leaving the menu up and re-marked.
---@param menu sidenote.menu.State
---@param row sidenote.menu.Row
local function pick(menu, row)
    local wrote = cycle.set(menu.entry, {
        field = row.field,
        value = row.value,
        config = menu.cfg,
        bufnr = menu.source,
    })
    if wrote then
        menu.rows = rows_for(menu.entry, menu.cfg)
        fill(menu.buf, menu.rows, menu.cfg)
    end
end

---Carry out `act` and dismiss the menu, unless its confirmation is declined.
---@param menu sidenote.menu.State
---@param act "open"|"view"|"delete"|"close"|nil what to do, nil on a rule row
local function run(menu, act)
    if act == "open" then
        M.close()
        local editor = vim.tbl_extend("force", menu.cfg.editor, { focus = true })
        local note = vim.tbl_extend("keep", { source = menu.source, config = menu.cfg }, menu.entry)
        require("sidenote.editor").open(note, editor, menu.cfg.filetype)
    elseif act == "view" then
        M.close()
        vim.schedule(function()
            require("sidenote").view()
        end)
    elseif act == "delete" then
        local summary = store.summary(menu.entry.root, menu.entry.id, menu.cfg.filetype)
        local asked = ('sidenote: delete "%s"?'):format(summary or "no prose")
        if vim.fn.confirm(asked, "&Delete\n&Cancel", 2) == 1 then
            store.delete(menu.entry.root, menu.entry.id, menu.cfg.filetype)
            M.close()
            require("sidenote.session").refresh(menu.source, menu.cfg)
        end
    else
        M.close()
    end
end

---Carry out whatever the row under the menu's cursor stands for.
---@param lnum integer 1-based menu line
local function activate(lnum)
    local menu = current
    local row = menu and menu.rows[lnum]
    if not menu or not row then
        return
    end
    if row.field then
        pick(menu, row)
    else
        run(menu, row.act)
    end
end

---Open the menu for the note under the cursor.
---@return integer|nil win nil when no note sits under the cursor
function M.open()
    local cfg = config.get()
    local entry = require("sidenote").at_cursor()
    if not entry then
        vim.notify("sidenote: no annotation under the cursor", vim.log.levels.WARN)
        return nil
    end
    M.close()

    local source = vim.api.nvim_get_current_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    local rows = rows_for(entry, cfg)
    fill(buf, rows, cfg)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "cursor",
        row = 1,
        col = 0,
        width = 30,
        height = #rows,
        style = "minimal",
        border = "rounded",
        title = " sidenote ",
        title_pos = "center",
    })
    vim.wo[win].cursorline = true
    current = { buf = buf, win = win, entry = entry, cfg = cfg, rows = rows, source = source }

    local function on(lhs, fn)
        vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })
    end
    on("<CR>", function()
        activate(vim.fn.line("."))
    end)
    -- The click has already moved the cursor by the time the button lifts
    on("<LeftRelease>", function()
        activate(vim.fn.line("."))
    end)
    on("<Esc>", M.close)
    for _, action in ipairs(ACTIONS) do
        on(action.key, function()
            if current then
                run(current, action.act)
            end
        end)
    end

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        once = true,
        desc = "Dismiss the menu once it loses focus",
        callback = M.close,
    })
    return win
end

return M
