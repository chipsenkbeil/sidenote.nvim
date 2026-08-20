local capture = require("sidenote.capture")
local menu = require("sidenote.menu")
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
---@return integer source
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
    return result, bufnr
end

---@param key string
local function press(key)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "x", false)
end

---@param win integer
---@return string[]
local function lines_of(win)
    return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

---Buffer line of the row reading `text`, or nil.
---@param win integer
---@param text string
---@return integer|nil
local function row_of(win, text)
    for i, line in ipairs(lines_of(win)) do
        if line:find(text, 1, true) then
            return i
        end
    end
    return nil
end

describe("menu", function()
    before_each(function()
        vim.g.sidenote = { strategy = "project", filetype = "org", pens = opts().pens }
    end)

    after_each(function()
        menu.close()
        vim.g.sidenote = nil
        local editor = require("sidenote.editor").winid()
        if editor then
            require("sidenote.window").close(editor)
        end
        vim.cmd("silent! %bwipeout!")
    end)

    it("lists every value the note could take, the current ones marked", function()
        on_note()
        local win = assert(menu.open())
        local body = table.concat(lines_of(win), "\n")
        assert.contains(body, "● note")
        assert.contains(body, "○ todo")
        assert.contains(body, "● open")
        assert.contains(body, "○ resolved")
        assert.contains(body, "● -")
        assert.contains(body, "○ blue")
        assert.contains(body, "o  open the note")
    end)

    it("warns rather than opening over unannotated code", function()
        local _, source = on_note()
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        assert.is_nil(menu.open())
        assert.truthy(vim.api.nvim_buf_is_valid(source))
    end)

    it("writes a picked value and keeps the menu open, marks moved", function()
        local result = on_note()
        local win = assert(menu.open())
        vim.api.nvim_win_set_cursor(win, { assert(row_of(win, "○ todo")), 0 })
        press("<CR>")

        assert.eq(assert(store.read(result.root, result.id)).kind, "todo")
        assert.truthy(vim.api.nvim_win_is_valid(win), "picking a value keeps the menu up")
        assert.not_nil(row_of(win, "● todo"))
    end)

    it("inks a picked pen onto the note", function()
        local result = on_note()
        local win = assert(menu.open())
        vim.api.nvim_win_set_cursor(win, { assert(row_of(win, "○ green")), 0 })
        press("<CR>")
        assert.eq(assert(store.read(result.root, result.id)).pen, "green")
    end)

    it("closes on q", function()
        on_note()
        local win = assert(menu.open())
        press("q")
        assert.falsy(vim.api.nvim_win_is_valid(win))
    end)

    it("deletes after a confirmation that quotes the summary", function()
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
        assert(menu.open())
        press("d")
        vim.fn.confirm = original

        assert.contains(asked, "the doomed note")
        assert.falsy(vim.uv.fs_stat(store.meta_path(result.root, result.id)))
    end)

    it("opens the note focused from its action row", function()
        on_note()
        local win = assert(menu.open())
        press("o")
        assert.falsy(vim.api.nvim_win_is_valid(win))
        local editor = assert(require("sidenote.editor").winid())
        assert.eq(vim.api.nvim_get_current_win(), editor)
    end)
end)
