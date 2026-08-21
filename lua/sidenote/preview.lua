local editor = require("sidenote.editor")
local highlight = require("sidenote.highlight")
local store = require("sidenote.store")
local window = require("sidenote.window")

---@class sidenote.preview.Opts
---@field style "float"|"virt_lines"|"split"|"none" where the note is shown
---@field max_lines integer most prose lines rendered in a preview
---@field filetype string extension and filetype of prose files
---@field bufnr integer source buffer the annotation belongs to
---@field config? sidenote.Config for the identity line's pens and ink

---Glance at a note without leaving the code.
---
---Owns a namespace separate from the indicator one, so dismissing a preview
---never clears the signs a buffer is showing.
---@class sidenote.preview
local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace("sidenote.preview")

local PLACEHOLDER = "(empty note)"

---Display columns the rule under a hanging glance's identity takes.
local DIVIDER_WIDTH = 40

---Display columns a glance's own window takes.
local WINDOW_WIDTH = 60

---Autocmd group holding the armed dismissal.
local GROUP = "sidenote.preview.dismiss"

---Window the glance sits in, closed by the next glance.
---@type integer|nil
local current

---Buffer a hanging glance is attached to.
---@type integer|nil
local attached

---The glance's window, if it is still open.
---@return integer|nil winid nil when nothing is showing, or when it hangs in the code
function M.winid()
    if current and vim.api.nvim_win_is_valid(current) then
        return current
    end
    return nil
end

function M.hide()
    pcall(vim.api.nvim_del_augroup_by_name, GROUP)
    window.close(M.winid())
    current = nil

    if attached and vim.api.nvim_buf_is_valid(attached) then
        vim.api.nvim_buf_clear_namespace(attached, M.NAMESPACE, 0, -1)
    end
    attached = nil
end

---Hide the preview at the first sign of doing anything else.
---
---Armed against the position it was shown for: the motion that opened the
---preview can flush its own CursorMoved after the fact, and that one must
---not dismiss it.
local function dismiss_later()
    local armed = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufLeave" }, {
        group = vim.api.nvim_create_augroup(GROUP, { clear = true }),
        desc = "Dismiss the sidenote preview once the glance is over",
        callback = function(event)
            local here = vim.api.nvim_win_get_cursor(0)
            if event.event ~= "CursorMoved" or here[1] ~= armed[1] or here[2] ~= armed[2] then
                M.hide()
            end
        end,
    })
end

---A note's prose, trailing blanks dropped and cut to what a glance shows.
---@param entry sidenote.session.Entry
---@param filetype string
---@param max_lines integer
---@return string[] lines
---@return integer dropped how many prose lines the glance is not showing
local function prose_lines(entry, filetype, max_lines)
    local prose = store.prose(entry.root, entry.id, filetype) or ""
    local lines = {}
    for line in (prose .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    while #lines > 0 and lines[#lines] == "" do
        lines[#lines] = nil
    end
    if #lines == 0 then
        return { PLACEHOLDER }, 0
    end
    local dropped = math.max(0, #lines - max_lines)
    while #lines > max_lines do
        lines[#lines] = nil
    end
    return lines, dropped
end

---The identity chunks for a glance, base color filled in.
---@param entry sidenote.session.Entry
---@param cfg sidenote.Config|nil
---@return {[1]: string, [2]: string}[]
local function identity(entry, cfg)
    local chunks = {}
    for _, chunk in ipairs(editor.identity(vim.tbl_extend("keep", { config = cfg }, entry))) do
        chunks[#chunks + 1] = { chunk[1], chunk[2] or highlight.CONTEXT }
    end
    return chunks
end

---One virtual line saying how much of the note the glance held back.
---@param dropped integer
---@return {[1]: string, [2]: string}[]
local function held_back(dropped)
    local text = ("… %d more — open the note to read it all"):format(dropped)
    return { { text, highlight.CONTEXT } }
end

---Hang the note under the annotated line as virtual text.
---
---Plain chunks, deliberately: giving prose its own filetype would mean
---rendering one language's markup inside another's buffer.
---@param entry sidenote.session.Entry
---@param virt {[1]: string, [2]: string}[][] chunk lines to hang
---@param bufnr integer
local function attach(entry, virt, bufnr)
    -- Clamping is how a note ends up beside code it was never about
    if not entry.line_end or entry.line_end > vim.api.nvim_buf_line_count(bufnr) then
        return
    end
    vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, entry.line_end - 1, 0, { virt_lines = virt })
    attached = bufnr
end

---Show a note's prose in the configured preview surface.
---
---A glance stays a glance: a note longer than `max_lines` is cut with a
---marker saying how much is held back, and reading it all means opening
---the note. The identity — location, kind, state, ink — sits in the
---float's winbar, or leads the virtual lines.
---@param entry sidenote.session.Entry
---@param opts sidenote.preview.Opts
function M.show(entry, opts)
    M.hide()
    if opts.style == "none" then
        return
    end

    local lines, dropped = prose_lines(entry, opts.filetype, opts.max_lines)
    if opts.style == "virt_lines" then
        local virt = {}
        if entry.record then
            virt[#virt + 1] = identity(entry, opts.config)
            virt[#virt + 1] = { { ("─"):rep(DIVIDER_WIDTH), highlight.CONTEXT } }
        end
        for _, line in ipairs(lines) do
            virt[#virt + 1] = { { line, "SidenoteProse" } }
        end
        if dropped > 0 then
            virt[#virt + 1] = held_back(dropped)
        end
        attach(entry, virt, opts.bufnr)
        dismiss_later()
        return
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = opts.filetype
    vim.bo[bufnr].modifiable = false
    if dropped > 0 then
        vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, #lines - 1, 0, {
            virt_lines = { held_back(dropped) },
        })
    end

    local style = opts.style == "split" and "split" or "float"
    current = window.open(bufnr, { style = style, position = "right", size = WINDOW_WIDTH })
    if entry.record then
        -- A float sized to its content has no row for the winbar yet
        local shape = vim.api.nvim_win_get_config(current)
        if shape.relative ~= "" then
            vim.api.nvim_win_set_config(current, { height = shape.height + 1 })
        end
        local note = vim.tbl_extend("keep", { config = opts.config }, entry)
        vim.api.nvim_set_option_value(
            "winbar",
            editor.headline(note),
            { win = current, scope = "local" }
        )
    end
    dismiss_later()
end

return M
