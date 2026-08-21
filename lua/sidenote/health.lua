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
---@param here string directory the report is about
local function report_project_store(cfg, here)
    local WRITABLE_DIRECTORY = 2

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

---Report what a capture standing here would actually record.
---
---A probe, not a PATH lookup: provenance is read through git, so an installed
---tool proves nothing about whether there is anything here for it to read.
---@param here string directory the report is about
local function report_vcs(here)
    local NOTHING_TO_READ = "no .git at or above %s, so annotations record no provenance;"
        .. " a jj repository with no colocated .git is the usual reason"

    if vim.fn.executable("git") == 0 then
        vim.health.info("git not found, so annotations record no provenance")
        return
    end

    local vcs = require("sidenote.store.vcs").probe(here)
    if vcs then
        vim.health.ok(("%s at %s, so annotations record provenance"):format(vcs.kind, here))
    else
        vim.health.info(NOTHING_TO_READ:format(here))
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

    local here = vim.fn.getcwd()
    report_global_store(cfg)
    report_project_store(cfg, here)
    report_vcs(here)
    report_prose(cfg)
end

return M
