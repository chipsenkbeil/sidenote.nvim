if vim.g.loaded_sidenote then
    return
end
vim.g.loaded_sidenote = true

local SUBCOMMANDS =
    { "add", "browse", "project", "refresh", "view", "open", "next", "prev", "highlight" }

---@param err string
local function report(err)
    vim.notify("sidenote: " .. err, vim.log.levels.ERROR)
end

---Values each filter key accepts, required lazily to keep loading lazy.
---@return table<string, string[]>
local function filter_values()
    local record = require("sidenote.core.record")
    local resolve = require("sidenote.core.resolve")
    return {
        status = resolve.STATUS_NAMES,
        kind = record.KIND_NAMES,
        state = record.STATE_NAMES,
    }
end

---Split a listing subcommand's arguments into a path and a validated filter.
---
---`status=`, `kind=` and `state=` narrow the listing, the way `:set` and
---`:Telescope` take options; anything else positional is the project path.
---A bad key or value is an error, since a filter nothing reads would silently
---match everything.
---@param fargs string[]
---@return string|nil path
---@return sidenote.browser.Filter|nil filter nil when a filter was invalid
---@return string|nil err
local function listing_args(fargs)
    local values = filter_values()
    local path, filter = nil, {}
    for i = 2, #fargs do
        local key, value = fargs[i]:match("^(%w+)=(.+)$")
        if not key then
            path = fargs[i]
        elseif key == "path" then
            -- Free-form: any substring of a project-relative path is fair
            filter.path = value
        elseif not values[key] then
            return nil,
                nil,
                ("unknown filter %q; expected kind=, path=, state= or status="):format(key)
        elseif not vim.tbl_contains(values[key], value) then
            return nil,
                nil,
                ("unknown %s %q; expected one of %s"):format(
                    key,
                    value,
                    table.concat(values[key], ", ")
                )
        else
            filter[key] = value
        end
    end
    return path, filter, nil
end

---Capture `first` through `last` as a lines-scope annotation.
---
---Always lines, never range: neither the command nor the mapping carries
---column information, and columns belong to range scope alone.
---@param first integer
---@param last integer
local function add(first, last)
    local sidenote = require("sidenote")
    -- Held before the capture: composing focuses the new note's window, so
    -- "current buffer" no longer names the annotated one afterwards
    local bufnr = vim.api.nvim_get_current_buf()
    local _, err = sidenote.add({ scope = "lines", range = { first, 0, last, 0 } })
    if err then
        report(err)
        return
    end
    sidenote.refresh(bufnr)
end

---Capture the whole current file as one annotation.
local function add_file()
    local sidenote = require("sidenote")
    local bufnr = vim.api.nvim_get_current_buf()
    local _, err = sidenote.add({ scope = "file" })
    if err then
        report(err)
        return
    end
    sidenote.refresh(bufnr)
end

vim.api.nvim_create_user_command("Sidenote", function(cmd)
    local subcommand = cmd.fargs[1]
    if subcommand == "add" then
        if cmd.fargs[2] == "scope=file" then
            add_file()
        elseif cmd.fargs[2] then
            report(("add takes only scope=file, not %q"):format(cmd.fargs[2]))
        else
            add(cmd.line1, cmd.line2)
        end
    elseif subcommand == "browse" then
        local path, filter, filter_err = listing_args(cmd.fargs)
        if filter_err then
            report(filter_err)
        elseif path then
            report("browse takes no path; use :Sidenote project " .. path)
        else
            local _, err = require("sidenote").browse({ filter = filter })
            if err then
                report(err)
            end
        end
    elseif subcommand == "project" then
        local path, filter, filter_err = listing_args(cmd.fargs)
        if filter_err then
            report(filter_err)
        else
            local _, err = require("sidenote").browse_project({ path = path, filter = filter })
            if err then
                report(err)
            end
        end
    elseif subcommand == "refresh" then
        require("sidenote").refresh()
    elseif subcommand == "highlight" then
        local shown = require("sidenote").toggle_highlight()
        if shown ~= nil then
            vim.notify("sidenote: highlights " .. (shown and "on" or "off"))
        end
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
    complete = function(arg_lead, cmd_line)
        ---@param candidates string[]
        local function matching(candidates)
            return vim.tbl_filter(function(name)
                return name:find(arg_lead, 1, true) == 1
            end, candidates)
        end

        -- Nothing but the lead after the command name: complete the subcommand
        local after = cmd_line:match("Sidenote%s+(.*)$") or ""
        if after == arg_lead then
            return matching(SUBCOMMANDS)
        end
        local subcommand = after:match("^(%S+)")
        if subcommand == "add" then
            return matching({ "scope=file" })
        end
        if subcommand ~= "browse" and subcommand ~= "project" then
            return {}
        end

        -- Filters: values for a known key, else the keys themselves
        local values = filter_values()
        local key = arg_lead:match("^(%w+)=")
        if key and values[key] then
            return matching(vim.tbl_map(function(value)
                return key .. "=" .. value
            end, values[key]))
        end
        return matching({ "kind=", "path=", "state=", "status=" })
    end,
})

vim.keymap.set({ "n", "x" }, "<Plug>(SidenoteAdd)", function()
    local first, last = vim.fn.line("v"), vim.fn.line(".")
    if first > last then
        first, last = last, first
    end
    add(first, last)
end, { desc = "Annotate the current line or selection" })

vim.keymap.set("n", "<Plug>(SidenoteAddFile)", function()
    add_file()
end, { desc = "Annotate the whole file" })

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

vim.keymap.set("n", "<Plug>(SidenoteToggleHighlight)", function()
    require("sidenote").toggle_highlight()
end, { desc = "Toggle range highlights in this buffer" })

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
