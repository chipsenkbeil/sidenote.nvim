local config = require("sidenote.config")
local filter = require("sidenote.filter")
local project = require("sidenote.store.project")

---Annotations as quickfix and location lists.
---
---The vim-native way to sweep a set of notes: populate, open, jump with
---the machinery every other tool already feeds.
---@class sidenote.list
local M = {}

---One list line: bracketed metadata, the summary, and a hurt status.
---@param entry sidenote.session.Entry
---@return string
local function label(entry)
    local rec = entry.record
    local parts = { rec.kind, rec.state }
    if rec.pen then
        parts[#parts + 1] = rec.pen
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
---@field bufnr? integer buffer a location list covers, defaulting to current
---@field path? string any file inside the project a quickfix list covers

---Fill the current window's location list with one buffer's annotations.
---@param opts? sidenote.list.Opts
---@return integer listed
function M.loclist(opts)
    opts = opts or {}
    local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
    local cfg = config.get()

    local items = {}
    local entries = require("sidenote.session").entries(bufnr, cfg)
    for _, entry in ipairs(filter.narrow(entries, opts.filter)) do
        items[#items + 1] = {
            bufnr = bufnr,
            lnum = entry.line_start or entry.record.line_start or 1,
            col = entry.col_start or 1,
            text = label(entry),
        }
    end

    vim.fn.setloclist(0, {}, " ", { title = "sidenote", items = items })
    if #items > 0 then
        vim.cmd.lopen()
    else
        vim.notify("sidenote: no annotations match", vim.log.levels.INFO)
    end
    return #items
end

---Fill the quickfix list with a whole project's annotations.
---@param opts? sidenote.list.Opts
---@return integer listed
function M.qflist(opts)
    opts = opts or {}
    local cfg = config.get()
    local from = opts.path
    if not from or from == "" then
        from = vim.api.nvim_buf_get_name(opts.bufnr or vim.api.nvim_get_current_buf())
    end
    if from == "" then
        from = vim.fn.getcwd()
    end
    local root = project.root(from)

    local items = {}
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
        }
    end

    vim.fn.setqflist({}, " ", { title = "sidenote", items = items })
    if #items > 0 then
        vim.cmd.copen()
    else
        vim.notify("sidenote: no annotations match", vim.log.levels.INFO)
    end
    return #items
end

return M
