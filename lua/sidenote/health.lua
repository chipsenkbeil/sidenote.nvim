---@class sidenote.health
local M = {}

function M.check()
    vim.health.start("sidenote")

    local cfg, err = require("sidenote.config").get()
    if err then
        vim.health.error(err)
    else
        vim.health.ok(("configuration valid, prose filetype %q"):format(cfg.filetype))
    end

    if vim.fn.executable("git") == 1 then
        vim.health.ok("git found, so annotations can record provenance")
    else
        vim.health.info("git not found; annotations will record no provenance")
    end

    if vim.fn.isdirectory(cfg.global_dir) == 1 or vim.fn.mkdir(cfg.global_dir, "p") == 1 then
        vim.health.ok(("global store writable at %s"):format(cfg.global_dir))
    else
        vim.health.error(("cannot create the global store at %s"):format(cfg.global_dir))
    end
end

return M
