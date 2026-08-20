local browser = require("sidenote.browser")
local capture = require("sidenote.capture")

---@return sidenote.Config
local function opts()
    return {
        filetype = "org",
        strategy = { "project" },
        project_dir = ".sidenote",
        global_dir = vim.fn.tempname(),
        indicator = { style = "sign" },
        preview = { style = "float", max_lines = 20 },
        editor = { style = "split", position = "right", size = 60 },
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---Build a project with one source file open in a buffer.
---@return integer bufnr
---@return string path
local function project_buffer()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.sidenote", "p")
    local path = root .. "/m.lua"
    local fh = assert(io.open(path, "w"))
    fh:write(table.concat(SOURCE, "\n") .. "\n")
    fh:close()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, SOURCE)
    return bufnr, assert(vim.uv.fs_realpath(path))
end

---@param bufnr integer
---@param line integer
local function annotate(bufnr, line)
    assert(capture.run(bufnr, { scope = "lines", range = { line, 0, line, 0 }, config = opts() }))
end

---@param keys string
local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

---The one floating window on screen, or nil.
---@return integer|nil
local function floating()
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(winid).relative ~= "" then
            return winid
        end
    end
    return nil
end

describe("browser gf", function()
    it("jumps to the annotated code in the listing's window", function()
        local source, path = project_buffer()
        annotate(source, 4)
        assert(browser.open(source, { config = opts() }))
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        press("gf")
        assert.eq(vim.api.nvim_buf_get_name(0), path)
        assert.eq(vim.api.nvim_win_get_cursor(0)[1], 4)
    end)

    it("refuses to jump for a note with no trusted position", function()
        -- The export gate's rule holds in the UI too: an orphan gets a
        -- message, never a guess at whatever sits on its old lines
        local source = project_buffer()
        annotate(source, 4)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { "entirely", "different", "words" })
        local listing = assert(browser.open(source, { config = opts() }))
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        local messages = {}
        local original = vim.notify
        vim.notify = function(msg)
            messages[#messages + 1] = tostring(msg)
        end
        press("gf")
        vim.notify = original

        assert.eq(vim.api.nvim_get_current_buf(), listing, "the listing must stay put")
        assert.contains(table.concat(messages, "\n"), "position")
    end)
end)

describe("browser toggling back", function()
    it("returns to the listed file when browsing from its listing", function()
        -- The alternative is a listing of the listing, which nobody wants;
        -- this makes one mapping a true toggle
        local source, path = project_buffer()
        annotate(source, 4)
        local listing = assert(browser.open(source, { config = opts() }))

        browser.open(listing, { config = opts() })
        assert.eq(vim.api.nvim_buf_get_name(0), path)
    end)

    it("stays put with a hint when a project listing has no one file", function()
        local source = project_buffer()
        annotate(source, 4)
        local name = vim.api.nvim_buf_get_name(source)
        local listing = assert(browser.open_project(name, { config = opts() }))

        local bufnr, err = browser.open(listing, { config = opts() })
        assert.is_nil(bufnr)
        assert.contains(err, "gf")
        assert.eq(vim.api.nvim_get_current_buf(), listing)
    end)
end)

describe("browser help", function()
    it("answers ? with a float listing every browser mapping", function()
        local source = project_buffer()
        annotate(source, 4)
        assert(browser.open(source, { config = opts() }))

        press("?")
        local winid = assert.not_nil(floating())
        local body = table.concat(
            vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(winid), 0, -1, false),
            "\n"
        )
        for _, key in ipairs({ "<CR>", "gf", "<Tab>", "-", "?" }) do
            assert.contains(body, key)
        end
        assert.contains(body, "za")
        press("q")
    end)

    it("closes the help again on q", function()
        local source = project_buffer()
        annotate(source, 4)
        assert(browser.open(source, { config = opts() }))

        press("?")
        assert.not_nil(floating())
        press("q")
        assert.is_nil(floating())
    end)
end)
