if vim.g.loaded_sidenote then
    return
end
vim.g.loaded_sidenote = true

local SUBCOMMANDS = { "add", "refresh" }

---@param err string
local function report(err)
    vim.notify("sidenote: " .. err, vim.log.levels.ERROR)
end

vim.api.nvim_create_user_command("Sidenote", function(cmd)
    local subcommand = cmd.fargs[1]
    if subcommand == "add" then
        local scope = cmd.range > 0 and "range" or "lines"
        local _, err = require("sidenote").add({
            scope = scope,
            range = { cmd.line1, 0, cmd.line2, 0 },
        })
        if err then
            report(err)
        else
            require("sidenote").refresh()
        end
    elseif subcommand == "refresh" then
        require("sidenote").refresh()
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
    local scope = first == last and "lines" or "range"
    local _, err = require("sidenote").add({ scope = scope, range = { first, 0, last, 0 } })
    if err then
        report(err)
    else
        require("sidenote").refresh()
    end
end, { desc = "Annotate the current line or selection" })

vim.keymap.set("n", "<Plug>(SidenoteRefresh)", function()
    require("sidenote").refresh()
end, { desc = "Re-resolve and repaint annotations" })

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
