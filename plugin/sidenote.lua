if vim.g.loaded_sidenote then
    return
end
vim.g.loaded_sidenote = true

local SUBCOMMANDS = { "add", "browse", "refresh", "view", "open", "next", "prev" }

---@param err string
local function report(err)
    vim.notify("sidenote: " .. err, vim.log.levels.ERROR)
end

---@param scope "file"|"lines"|"range"
---@param first integer
---@param last integer
local function add(scope, first, last)
    local sidenote = require("sidenote")
    local _, err = sidenote.add({ scope = scope, range = { first, 0, last, 0 } })
    if err then
        report(err)
        return
    end
    sidenote.refresh()
end

vim.api.nvim_create_user_command("Sidenote", function(cmd)
    local subcommand = cmd.fargs[1]
    if subcommand == "add" then
        add(cmd.range > 0 and "range" or "lines", cmd.line1, cmd.line2)
    elseif subcommand == "browse" then
        local _, err = require("sidenote").browse()
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
    add(first == last and "lines" or "range", first, last)
end, { desc = "Annotate the current line or selection" })

vim.keymap.set("n", "<Plug>(SidenoteBrowse)", function()
    local _, err = require("sidenote").browse()
    if err then
        report(err)
    end
end, { desc = "Open the editable listing of this file's annotations" })

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
vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
    group = group,
    desc = "Re-resolve annotations from disk; a surviving extmark is never trusted",
    callback = function(event)
        pcall(require("sidenote").refresh, event.buf)
    end,
})
vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    desc = "Redefine highlight groups after a colorscheme replaces them",
    callback = function()
        require("sidenote.highlight").setup()
    end,
})
