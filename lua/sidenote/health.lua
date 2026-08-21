---What `:checkhealth sidenote` reports.
---
---Every optional capability is reported as info rather than a warning: the
---plugin has no required dependencies, so a missing tool is a smaller feature
---set and never a fault.
---@class sidenote.health
local M = {}

---@param cfg sidenote.Config
local function report_global_store(cfg)
    if vim.fn.isdirectory(cfg.global_dir) == 1 or vim.fn.mkdir(cfg.global_dir, "p") == 1 then
        vim.health.ok(("global store writable at %s"):format(cfg.global_dir))
    else
        vim.health.error(("cannot create the global store at %s"):format(cfg.global_dir))
    end
end

---@param cfg sidenote.Config
local function report_project_store(cfg)
    local WRITABLE_DIRECTORY = 2

    local here = vim.fn.getcwd()
    local root = require("sidenote.store.project").root(here)
    if not root then
        vim.health.info(
            ("no project root at or above %s; notes here go to the global store"):format(here)
        )
        return
    end

    local dir = root .. "/" .. cfg.project_dir
    if vim.fn.isdirectory(dir) ~= 1 then
        vim.health.info(("project root %s, with no store yet at %s"):format(root, dir))
    elseif vim.fn.filewritable(dir) == WRITABLE_DIRECTORY then
        local count = #require("sidenote.store").ids(dir)
        vim.health.ok(("project store at %s holds %d annotation(s)"):format(dir, count))
    else
        vim.health.error(("project store at %s is not writable"):format(dir))
    end
end

local function report_vcs()
    local found = {}
    for _, tool in ipairs({ "git", "jj" }) do
        if vim.fn.executable(tool) == 1 then
            found[#found + 1] = tool
        end
    end
    if #found > 0 then
        vim.health.ok(
            ("%s found, so annotations record provenance"):format(table.concat(found, " and "))
        )
    else
        vim.health.info("neither git nor jj found; annotations will record no provenance")
    end
end

---@param cfg sidenote.Config
local function report_prose(cfg)
    if cfg.filetype == "org" and not pcall(require, "orgmode") then
        vim.health.info("prose filetype is org, but nvim-orgmode is not installed")
    end
end

function M.check()
    vim.health.start("sidenote")

    local cfg, err = require("sidenote.config").get()
    if err then
        vim.health.error(err)
    else
        vim.health.ok(("configuration valid, prose filetype %q"):format(cfg.filetype))
    end

    report_global_store(cfg)
    report_project_store(cfg)
    report_vcs()
    report_prose(cfg)
end

return M
