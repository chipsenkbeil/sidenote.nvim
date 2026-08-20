if vim.g.loaded_sidenote then
    return
end
vim.g.loaded_sidenote = true

local SUBCOMMANDS = { "add", "browse", "project", "refresh", "view", "open", "next", "prev" }

---@param err string
local function report(err)
    vim.notify("sidenote: " .. err, vim.log.levels.ERROR)
end

---Split a listing subcommand's arguments into a path and a filter.
---
---`--status=`, `--kind=` and `--state=` narrow the listing; anything else
---positional is the project path.
---@param fargs string[]
---@return string|nil path
---@return sidenote.browser.Filter filter
local function listing_args(fargs)
    local path, filter = nil, {}
    for i = 2, #fargs do
        local key, value = fargs[i]:match("^%-%-(%w+)=(.+)$")
        if key then
            filter[key] = value
        else
            path = fargs[i]
        end
    end
    return path, filter
end

---Capture `first` through `last` as a lines-scope annotation.
---
---Always lines, never range: neither the command nor the mapping carries
---column information, and columns belong to range scope alone.
---@param first integer
---@param last integer
local function add(first, last)
    local sidenote = require("sidenote")
    local _, err = sidenote.add({ scope = "lines", range = { first, 0, last, 0 } })
    if err then
        report(err)
        return
    end
    sidenote.refresh()
end

vim.api.nvim_create_user_command("Sidenote", function(cmd)
    local subcommand = cmd.fargs[1]
    if subcommand == "add" then
        add(cmd.line1, cmd.line2)
    elseif subcommand == "browse" then
        local path, filter = listing_args(cmd.fargs)
        local _, err = require("sidenote").browse({ filter = filter })
        if path then
            report("browse takes no path; use :Sidenote project " .. path)
        elseif err then
            report(err)
        end
    elseif subcommand == "project" then
        local path, filter = listing_args(cmd.fargs)
        local _, err = require("sidenote").browse_project({ path = path, filter = filter })
        if err then
            report(err)
        end
    elseif subcommand == "refresh" then
        require("sidenote").refresh()
    elseif subcommand == "view" or subcommand == "open" then
        if not require("sidenote")[subcommand]() then
            report("no annotation under the cursor")
        end
    elseif subcommand == "next" or subcommand == "prev" then
        if not require("sidenote")[subcommand]() then
            report("no annotation to jump to")
        end
    else
        report(("unknown command %q"):format(tostring(subcommand)))
    end
end, {
    nargs = "+",
    range = true,
    desc = "Annotate source code with notes stored outside the file",
    complete = function(arg_lead)
        return vim.tbl_filter(function(name)
            return name:find(arg_lead, 1, true) == 1
        end, SUBCOMMANDS)
    end,
})

vim.keymap.set({ "n", "x" }, "<Plug>(SidenoteAdd)", function()
    local first, last = vim.fn.line("v"), vim.fn.line(".")
    if first > last then
        first, last = last, first
    end
    add(first, last)
end, { desc = "Annotate the current line or selection" })

vim.keymap.set("n", "<Plug>(SidenoteBrowse)", function()
    local _, err = require("sidenote").browse()
    if err then
        report(err)
    end
end, { desc = "Open the editable listing of this file's annotations" })

vim.keymap.set("n", "<Plug>(SidenoteBrowseProject)", function()
    local _, err = require("sidenote").browse_project()
    if err then
        report(err)
    end
end, { desc = "Open the editable listing of every annotation in the project" })

vim.keymap.set("n", "<Plug>(SidenoteRefresh)", function()
    require("sidenote").refresh()
end, { desc = "Re-resolve and repaint annotations" })

vim.keymap.set("n", "<Plug>(SidenoteView)", function()
    require("sidenote").view()
end, { desc = "Preview the annotation under the cursor" })

vim.keymap.set("n", "<Plug>(SidenoteOpen)", function()
    require("sidenote").open()
end, { desc = "Open the annotation under the cursor for writing" })

vim.keymap.set("n", "<Plug>(SidenoteViewNext)", function()
    require("sidenote").next()
end, { desc = "Jump to the next annotation and preview it" })

vim.keymap.set("n", "<Plug>(SidenoteViewPrev)", function()
    require("sidenote").prev()
end, { desc = "Jump to the previous annotation and preview it" })

local group = vim.api.nvim_create_augroup("sidenote", { clear = true })
vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    desc = "Re-resolve annotations from disk; a surviving extmark is never trusted",
    callback = function(event)
        pcall(require("sidenote").refresh, event.buf)
    end,
})
vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    desc = "Write back verified anchors, then repaint from the updated records",
    callback = function(event)
        pcall(function()
            require("sidenote.session").written(event.buf)
            require("sidenote").refresh(event.buf)
        end)
    end,
})
vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    desc = "Redefine highlight groups after a colorscheme replaces them",
    callback = function()
        require("sidenote.highlight").setup()
    end,
})
