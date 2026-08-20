local window = require("sidenote.window")

---One cheat sheet for every listing surface, answering `g?` the way oil does.
---
---A surface passes the same actions table its keys were bound from, so the
---help can never drift from what the keys do.
---@class sidenote.help
local M = {}

---Show `actions` as a float; `q`, `<Esc>` and `g?` close it again.
---@param actions {lhs: string, desc: string}[] the mappings, in binding order
---@param opts? {footer?: string[]} extra lines below the mappings
function M.show(actions, opts)
    local lines = {}
    for _, action in ipairs(actions) do
        lines[#lines + 1] = ("  %-8s %s"):format(action.lhs, action.desc)
    end
    vim.list_extend(lines, opts and opts.footer or {})
    local width = 0
    for _, line in ipairs(lines) do
        width = math.max(width, #line)
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].bufhidden = "wipe"

    local winid = window.open(bufnr, { style = "float", size = width + 2, focus = true })
    for _, lhs in ipairs({ "q", "<Esc>", "g?" }) do
        vim.keymap.set("n", lhs, function()
            window.close(winid)
        end, { buffer = bufnr, nowait = true })
    end
end

return M
