---Where a listing opens: the configured surface, reuse, and how the verbs
---that leave it land.

local browser = require("sidenote.browser")
local fixture = require("spec.fixture")

---@param style? string how the listing opens, a bottom split by default
---@return sidenote.Config
local function opts(style)
    return fixture.opts({
        pens = { blue = "SidenotePenBlue" },
        browser = { style = style or "split", position = "bottom" },
    })
end

---@return integer bufnr
---@return string path resolved absolute path of the annotated file
local function project_buffer()
    local bufnr, _, path = fixture.project_buffer()
    return bufnr, path
end

---@param bufnr integer
---@param line integer
---@return sidenote.capture.Result
local function annotate(bufnr, line)
    return fixture.annotate({ bufnr = bufnr, line = line, config = opts() })
end

---@param keys string
local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

---@return integer
local function window_count()
    return #vim.api.nvim_tabpage_list_wins(0)
end

---@param winid integer
---@return boolean
local function floating(winid)
    return vim.api.nvim_win_get_config(winid).relative ~= ""
end

describe("browser placement", function()
    before_each(function()
        -- A stale listing left current by an earlier spec would take the
        -- in-place reuse branch and hide the fresh surface under test
        vim.cmd("silent! only!")
        vim.cmd.enew()
    end)

    after_each(function()
        -- A note window left open is reused by the next spec's editor.open
        local editor = require("sidenote.editor")
        if editor.winid() and window_count() == 1 then
            vim.cmd.split()
        end
        require("sidenote.window").close(editor.winid())
        vim.cmd("silent! only!")
        vim.cmd("silent! %bwipeout!")
    end)

    it("opens a bottom split sized to its rows by default", function()
        local source = project_buffer()
        annotate(source, 1)
        local before = vim.api.nvim_get_current_win()

        local listing = assert(browser.open(source, { config = opts() }))

        local winid = vim.api.nvim_get_current_win()
        assert.neq(winid, before, "the listing takes its own window")
        assert.eq(floating(winid), false)
        assert.eq(vim.api.nvim_win_get_buf(winid), listing)
        assert.eq(vim.api.nvim_win_get_height(winid), 3, "one note fits the minimum strip")
        assert.eq(vim.api.nvim_win_is_valid(before), true)
    end)

    it("focuses the listing window it already has instead of stacking", function()
        local source = project_buffer()
        annotate(source, 1)
        assert(browser.open(source, { config = opts() }))
        local opened = window_count()

        press("<C-w>p")
        assert(browser.open(source, { config = opts() }))
        assert.eq(window_count(), opened, "the second open made no second window")
    end)

    it("keeps the takeover behavior under style current", function()
        local source = project_buffer()
        annotate(source, 1)
        vim.api.nvim_win_set_buf(0, source)
        local before = vim.api.nvim_get_current_win()
        local count = window_count()

        local listing = assert(browser.open(source, { config = opts("current") }))

        assert.eq(vim.api.nvim_get_current_win(), before)
        assert.eq(window_count(), count)
        assert.eq(vim.api.nvim_win_get_buf(before), listing)
    end)

    it("widens in place rather than opening a second surface", function()
        local source = project_buffer()
        annotate(source, 1)
        assert(browser.open(source, { config = opts() }))
        local winid = vim.api.nvim_get_current_win()
        local count = window_count()

        press("-")

        assert.eq(vim.api.nvim_get_current_win(), winid)
        assert.eq(window_count(), count)
        local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(winid))
        assert.match(name, "/$", "the trailing slash marks a project listing")
    end)

    it("gf from a split lands in the window you came from", function()
        local source, path = project_buffer()
        annotate(source, 1)
        local origin = vim.api.nvim_get_current_win()

        local listing = assert(browser.open(source, { config = opts() }))
        local strip = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        press("gf")

        assert.eq(vim.api.nvim_get_current_win(), origin)
        assert.eq(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()), path)
        assert.eq(vim.api.nvim_win_get_buf(strip), listing, "the strip stays, quickfix-style")
    end)

    it("gf from a float closes it before landing", function()
        local source, path = project_buffer()
        annotate(source, 1)

        assert(browser.open(source, { config = opts("float") }))
        assert.eq(floating(vim.api.nvim_get_current_win()), true)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        press("gf")

        for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            assert.eq(floating(winid), false, "no float outlives the jump")
        end
        assert.eq(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()), path)
    end)

    it("opens the note editor beside the origin window, not inside the strip", function()
        local source = project_buffer()
        annotate(source, 1)
        local origin = vim.api.nvim_get_current_win()

        local listing = assert(browser.open(source, { config = opts() }))
        local strip = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        press("<CR>")

        local editor = require("sidenote.editor")
        local opened = assert.not_nil(editor.winid())
        assert.eq(vim.api.nvim_win_get_buf(strip), listing, "the strip stays put")
        assert.eq(
            vim.api.nvim_win_get_height(opened),
            vim.api.nvim_win_get_height(origin),
            "the editor split shares the origin's height, not the strip's"
        )
    end)
end)
