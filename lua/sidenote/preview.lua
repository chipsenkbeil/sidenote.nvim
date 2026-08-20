local store = require("sidenote.store")
local window = require("sidenote.window")

---@class sidenote.preview.Opts
---@field style "float"|"virt_lines"|"split"|"none" where the note is shown
---@field max_lines integer most prose lines rendered in a preview
---@field filetype string extension and filetype of prose files
---@field bufnr integer source buffer the annotation belongs to

---Glance at a note without leaving the code.
---
---Owns a namespace separate from the indicator one, so dismissing a preview
---never clears the signs a buffer is showing.
---@class sidenote.preview
local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace("sidenote.preview")

local PLACEHOLDER = "(empty note)"

---@type integer|nil
local current

---@type integer|nil
local attached

---@return integer|nil winid
function M.winid()
    if current and vim.api.nvim_win_is_valid(current) then
        return current
    end
    return nil
end

---Autocmd group holding the armed dismissal, cleared alongside the preview.
local GROUP = "sidenote.preview.dismiss"

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
---A glance is transient, the way a hover is. Armed against the position it
---was shown for: the motion that opened the preview can flush its own
---CursorMoved after the fact, and that one must not dismiss it.
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

---@param entry sidenote.session.Entry
---@param filetype string
---@param max_lines integer
---@return string[]
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
        return { PLACEHOLDER }
    end
    while #lines > max_lines do
        lines[#lines] = nil
    end
    return lines
end

---Hang the prose under the annotated line as virtual text.
---
---Plain text, deliberately: giving it the prose filetype would mean rendering
---one language's markup inside another's buffer, which is out of scope.
---@param entry sidenote.session.Entry
---@param lines string[]
---@param bufnr integer
local function attach(entry, lines, bufnr)
    -- An unplaced or out-of-range annotation is skipped rather than clamped:
    -- clamping is how a note ends up beside code it was never about
    if not entry.line_end or entry.line_end > vim.api.nvim_buf_line_count(bufnr) then
        return
    end

    local virt = {}
    for i, line in ipairs(lines) do
        virt[i] = { { line, "SidenoteProse" } }
    end
    vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, entry.line_end - 1, 0, { virt_lines = virt })
    attached = bufnr
end

---Show a note's prose in the configured preview surface.
---@param entry sidenote.session.Entry
---@param opts sidenote.preview.Opts
function M.show(entry, opts)
    M.hide()
    if opts.style == "none" then
        return
    end

    local lines = prose_lines(entry, opts.filetype, opts.max_lines)
    if opts.style == "virt_lines" then
        attach(entry, lines, opts.bufnr)
        dismiss_later()
        return
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = opts.filetype
    vim.bo[bufnr].modifiable = false

    local style = opts.style == "split" and "split" or "float"
    current = window.open(bufnr, { style = style, position = "right", size = 60 })
    dismiss_later()
end

return M
