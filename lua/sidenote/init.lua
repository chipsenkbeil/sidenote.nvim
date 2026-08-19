---Public Lua API.
---@class sidenote
local M = {}

---Annotate the current buffer.
---@param opts sidenote.capture.Opts
---@return sidenote.capture.Result|nil
---@return string|nil err
function M.add(opts)
    return require("sidenote.capture").run(vim.api.nvim_get_current_buf(), opts)
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

return M
