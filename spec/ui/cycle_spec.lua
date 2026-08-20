local capture = require("sidenote.capture")
local cycle = require("sidenote.cycle")
local store = require("sidenote.store")

---@return sidenote.Config
local function opts()
    return {
        filetype = "org",
        strategy = { "project" },
        project_dir = ".sidenote",
        global_dir = vim.fn.tempname(),
        pens = { blue = "SidenotePenBlue", green = "SidenotePenGreen" },
        indicator = { style = "sign", highlight = "off" },
        preview = { style = "float", max_lines = 20 },
        editor = { style = "split", position = "right", size = 40 },
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---Annotate line 4 of a real file and land the cursor on it.
---@return sidenote.capture.Result
local function on_note()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.sidenote", "p")
    local path = root .. "/m.lua"
    local fh = assert(io.open(path, "w"))
    fh:write(table.concat(SOURCE, "\n") .. "\n")
    fh:close()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, SOURCE)
    local result =
        assert(capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() }))
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    return result
end

describe("cycle.at_cursor", function()
    before_each(function()
        vim.g.sidenote = { strategy = "project", filetype = "org", pens = opts().pens }
    end)

    after_each(function()
        vim.g.sidenote = nil
        vim.cmd("silent! %bwipeout!")
    end)

    it("rotates the state of the note under the cursor, both ways", function()
        local result = on_note()
        assert.truthy(cycle.at_cursor("state", 1))
        assert.eq(assert(store.read(result.root, result.id)).state, "resolved")
        assert.truthy(cycle.at_cursor("state", -1))
        assert.eq(assert(store.read(result.root, result.id)).state, "open")
    end)

    it("flips the kind", function()
        local result = on_note()
        assert.truthy(cycle.at_cursor("kind", 1))
        assert.eq(assert(store.read(result.root, result.id)).kind, "todo")
    end)

    it("rotates the pen through none and every configured name", function()
        local result = on_note()
        assert.truthy(cycle.at_cursor("pen", 1))
        assert.eq(assert(store.read(result.root, result.id)).pen, "blue")
        assert.truthy(cycle.at_cursor("pen", -1))
        assert.is_nil(assert(store.read(result.root, result.id)).pen)
    end)

    it("says no when nothing sits under the cursor", function()
        on_note()
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        assert.falsy(cycle.at_cursor("state", 1))
    end)
end)

describe("sidenote.delete", function()
    before_each(function()
        vim.g.sidenote = { strategy = "project", filetype = "org" }
    end)

    after_each(function()
        vim.g.sidenote = nil
        vim.cmd("silent! %bwipeout!")
    end)

    it("deletes the note under the cursor after a quoting confirmation", function()
        local result = on_note()
        local fh = assert(io.open(store.prose_path(result.root, result.id, "org"), "w"))
        fh:write("the doomed note\n")
        fh:close()

        local asked
        local original = vim.fn.confirm
        vim.fn.confirm = function(prompt)
            asked = prompt
            return 1
        end
        local deleted = require("sidenote").delete()
        vim.fn.confirm = original

        assert.truthy(deleted)
        assert.contains(asked, "the doomed note")
        assert.falsy(vim.uv.fs_stat(store.meta_path(result.root, result.id)))
    end)

    it("keeps the note when the confirmation is declined", function()
        local result = on_note()
        local original = vim.fn.confirm
        vim.fn.confirm = function()
            return 2
        end
        assert.falsy(require("sidenote").delete())
        vim.fn.confirm = original
        assert.truthy(vim.uv.fs_stat(store.meta_path(result.root, result.id)))
    end)
end)
