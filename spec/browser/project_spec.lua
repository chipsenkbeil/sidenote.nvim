local browser = require("sidenote.browser")
local capture = require("sidenote.capture")
local store = require("sidenote.store")

---@return sidenote.Config
local function opts()
    return {
        filetype = "org",
        strategy = { "project" },
        project_dir = ".annotations",
        global_dir = vim.fn.tempname(),
        indicator = { style = "sign" },
        preview = { style = "float", max_lines = 20 },
        editor = { style = "split", position = "right", size = 60 },
    }
end

local ALPHA = { "local M = {}", "", "function M.f()", "  return 1", "end" }
local BETA = { "-- beta", "local x = 1", "return x" }

---@class spec.browser.Tree
---@field root string project root on disk
---@field alpha integer buffer holding alpha.lua

---@return spec.browser.Tree
local function tree()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.annotations", "p")
    for name, lines in pairs({ ["alpha.lua"] = ALPHA, ["beta.lua"] = BETA }) do
        local fh = assert(io.open(root .. "/" .. name, "w"))
        fh:write(table.concat(lines, "\n") .. "\n")
        fh:close()
    end
    root = assert(vim.uv.fs_realpath(root))

    local alpha = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(alpha, root .. "/alpha.lua")
    vim.api.nvim_buf_set_lines(alpha, 0, -1, false, ALPHA)
    return { root = root, alpha = alpha }
end

---@param root string
---@param name string
---@param line integer
---@param prose string[]
---@return string id
local function annotate(root, name, line, prose)
    local path = root .. "/" .. name
    local bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)

    local cfg = opts()
    local result =
        assert(capture.run(bufnr, { scope = "lines", range = { line, 0, line, 0 }, config = cfg }))
    local note = assert(io.open(store.prose_path(result.root, result.id, cfg.filetype), "w"))
    note:write(table.concat(prose, "\n") .. "\n")
    note:close()
    return result.id
end

describe("browser.open_project", function()
    it("names the buffer after the project root, with a trailing slash", function()
        -- A directory reads that way, and it keeps the name distinct from a
        -- file listing for a file that happens to share the path
        local t = tree()
        local bufnr = assert(browser.open_project(t.root, { config = opts() }))
        assert.eq(vim.api.nvim_buf_get_name(bufnr), "sidenote://" .. t.root .. "/")
    end)

    it("lists annotations from every file in the project", function()
        local t = tree()
        annotate(t.root, "alpha.lua", 4, { "in alpha" })
        annotate(t.root, "beta.lua", 2, { "in beta" })

        local bufnr = assert(browser.open_project(t.root, { config = opts() }))
        local state = assert(browser.state(bufnr))
        assert.eq(#state.rows, 2)
        assert.eq(state.scope, "project")
    end)

    it("sorts by path then line, so the listing reads the same every time", function()
        local t = tree()
        annotate(t.root, "beta.lua", 3, { "third" })
        annotate(t.root, "alpha.lua", 4, { "second" })
        annotate(t.root, "alpha.lua", 1, { "first" })

        local bufnr = assert(browser.open_project(t.root, { config = opts() }))
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        assert.contains(lines[1], "first")
        assert.contains(lines[2], "second")
        assert.contains(lines[3], "third")
    end)

    it("shows each row's own file in its location column", function()
        local t = tree()
        annotate(t.root, "beta.lua", 2, { "in beta" })
        local bufnr = assert(browser.open_project(t.root, { config = opts() }))
        assert.contains(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1], "beta.lua:2")
    end)

    it("accepts a file inside the project, not only the root", function()
        local t = tree()
        annotate(t.root, "alpha.lua", 4, { "the note" })
        local bufnr = assert(browser.open_project(t.root .. "/beta.lua", { config = opts() }))
        assert.eq(assert(browser.state(bufnr)).path, t.root)
    end)

    it("reuses the buffer when the project is browsed again", function()
        local t = tree()
        local first = assert(browser.open_project(t.root, { config = opts() }))
        assert.eq(browser.open_project(t.root, { config = opts() }), first)
    end)

    it("is a different buffer from the file listing for the same tree", function()
        local t = tree()
        local file_view = assert(browser.open(t.alpha, { config = opts() }))
        local project_view = assert(browser.open_project(t.root, { config = opts() }))
        assert.neq(file_view, project_view)
    end)

    it("refuses a path with no project root above it", function()
        local loose = vim.fn.tempname()
        vim.fn.mkdir(loose, "p")
        local bufnr, err = browser.open_project(loose, { config = opts() })
        assert.is_nil(bufnr)
        assert.contains(err, "no project root")
    end)

    it("opens folded shut, like the file listing", function()
        local t = tree()
        annotate(t.root, "alpha.lua", 4, { "summary", "a body line" })
        assert(browser.open_project(t.root, { config = opts() }))
        assert.eq(vim.fn.foldclosed(1), 1)
        assert.eq(vim.fn.foldclosedend(1), 2)
    end)
end)

describe("browser `-` goes up", function()
    ---@param bufnr integer
    ---@param lhs string
    ---@return function|nil
    local function mapping(bufnr, lhs)
        for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
            if map.lhs == lhs then
                return map.callback
            end
        end
        return nil
    end

    it("binds `-` inside the listing, where it is free", function()
        local t = tree()
        local bufnr = assert(browser.open(t.alpha, { config = opts() }))
        assert.is_type(mapping(bufnr, "-"), "function")
    end)

    it("widens a file listing to the project it belongs to", function()
        local t = tree()
        annotate(t.root, "beta.lua", 2, { "in another file" })
        local file_view = assert(browser.open(t.alpha, { config = opts() }))

        assert(mapping(file_view, "-"))()
        local now = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
        assert.neq(now, file_view)
        assert.eq(assert(browser.state(now)).scope, "project")
    end)

    it("does nothing in a listing that is already project-wide", function()
        local t = tree()
        local project_view = assert(browser.open_project(t.root, { config = opts() }))
        assert(mapping(project_view, "-"))()
        assert.eq(vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win()), project_view)
    end)
end)

describe("browser project edits", function()
    it("applies a delete to an annotation in another file", function()
        local t = tree()
        annotate(t.root, "alpha.lua", 4, { "keep me" })
        local doomed = annotate(t.root, "beta.lua", 2, { "delete me" })

        local bufnr = assert(browser.open_project(t.root, { config = opts() }))
        local state = assert(browser.state(bufnr))
        local root = state.rows[2].entry.root

        vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, {})
        assert.eq(
            browser.write(bufnr, {
                confirm = function()
                    return true
                end,
            }),
            1
        )
        assert.falsy(vim.uv.fs_stat(store.meta_path(root, doomed)))
    end)

    it("creates an annotation on whichever file the row names", function()
        -- A project listing spans many files, so the browser's own path cannot
        -- be what a create means
        local t = tree()
        local bufnr = assert(browser.open_project(t.root, { config = opts() }))

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
            "note  open      beta.lua    a brand new note",
        })
        assert.eq(
            browser.write(bufnr, {
                confirm = function()
                    return true
                end,
            }),
            1
        )

        local state = assert(browser.state(bufnr))
        assert.eq(#state.rows, 1)
        assert.eq(state.rows[1].entry.record.path, "beta.lua")
        assert.eq(state.rows[1].entry.record.scope, "file")
        assert.eq_deep(state.rows[1].prose, { "a brand new note" })
    end)
end)
