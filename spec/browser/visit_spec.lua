local browser = require("sidenote.browser")
local fixture = require("spec.fixture")
local highlight = require("sidenote.highlight")
local render = require("sidenote.render")
local session = require("sidenote.session")
local store = require("sidenote.store")

---@return sidenote.Config
local function opts()
    return fixture.opts({
        pens = { blue = "SidenotePenBlue", green = "SidenotePenGreen" },
        browser = { style = "current" },
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
---@param prose? string[]
---@return sidenote.capture.Result
local function annotate(bufnr, line, prose)
    return fixture.annotate({ bufnr = bufnr, line = line, prose = prose, config = opts() })
end

---@param keys string
local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

---Find the one floating window on screen.
---@return integer|nil winid nil when no float is open
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

describe("browser widening from a listing", function()
    it("widens a file listing to its project", function()
        -- The listing's own buffer name is sidenote://…, which is no path;
        -- what it lists is
        local source = project_buffer()
        annotate(source, 4)
        vim.api.nvim_set_current_buf(assert(browser.open(source, { config = opts() })))

        local sidenote = require("sidenote")
        vim.g.sidenote = { strategy = "project" }
        local listing, err = sidenote.browse_project({})
        vim.g.sidenote = nil

        assert.is_nil(err)
        local name = vim.api.nvim_buf_get_name(assert.not_nil(listing))
        assert.match(name, "^sidenote://.*/$")
    end)

    it("re-shows a project listing rather than erroring", function()
        local source = project_buffer()
        annotate(source, 4)
        local name = vim.api.nvim_buf_get_name(source)
        local listing = assert(browser.open_project(name, { config = opts() }))
        vim.api.nvim_set_current_buf(listing)

        local sidenote = require("sidenote")
        vim.g.sidenote = { strategy = "project" }
        local again, err = sidenote.browse_project({})
        vim.g.sidenote = nil

        assert.is_nil(err)
        assert.eq(again, listing)
    end)
end)

describe("verbs aimed at a listing", function()
    it("refuses to capture an annotation on the listing itself", function()
        local source = project_buffer()
        annotate(source, 4)
        local listing = assert(browser.open(source, { config = opts() }))
        vim.api.nvim_set_current_buf(listing)

        vim.g.sidenote = { strategy = "project" }
        local result, err = require("sidenote").add({ scope = "file" })
        vim.g.sidenote = nil

        assert.is_nil(result)
        assert.contains(err, "view")
    end)

    it("keeps the listing's status signs through a stray refresh", function()
        -- The browser paints its gutter into the shared namespace; a refresh
        -- aimed at the listing must not wipe what it cannot repaint
        local source = project_buffer()
        annotate(source, 4)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { "entirely", "different", "words" })
        local listing = assert(browser.open(source, { config = opts() }))
        vim.api.nvim_set_current_buf(listing)

        session.refresh(listing, opts())
        local marks = vim.api.nvim_buf_get_extmarks(listing, render.NAMESPACE, 0, -1, {})
        assert.eq(#marks, 1)
    end)
end)

describe("browser gutter", function()
    it("stays empty while every note is healthy", function()
        -- In a listing the row itself says the note exists; the gutter only
        -- earns ink when an anchor is hurt, so a ! can actually stand out
        local source = project_buffer()
        annotate(source, 4)
        local listing = assert(browser.open(source, { config = opts() }))

        local marks = vim.api.nvim_buf_get_extmarks(listing, render.NAMESPACE, 0, -1, {})
        assert.eq(#marks, 0)
    end)

    it("marks the row of a note whose anchor is hurt", function()
        local source = project_buffer()
        annotate(source, 4)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { "entirely", "different", "words" })
        local listing = assert(browser.open(source, { config = opts() }))

        local marks =
            vim.api.nvim_buf_get_extmarks(listing, render.NAMESPACE, 0, -1, { details = true })
        assert.eq(#marks, 1)
        assert.eq(vim.trim(marks[1][4].sign_text), highlight.SIGNS.orphaned)
    end)

    it("never draws the range overlay in a listing, even toggled on there", function()
        -- The listing is text about notes, not annotated code, so ink
        -- belongs to the source buffer alone
        local source = project_buffer()
        annotate(source, 4)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { "entirely", "different", "words" })

        local listing = assert(browser.open(source, { config = opts() }))
        render.toggle(listing, { configured = "off" })
        assert(browser.open(source, { config = opts() }))

        local marks = vim.api.nvim_buf_get_extmarks(listing, render.NAMESPACE, 0, -1, {
            details = true,
        })
        assert.gt(#marks, 0, "the status sign itself must survive")
        for _, mark in ipairs(marks) do
            assert.is_nil(mark[4].hl_group, "overlay ink in the listing")
        end
    end)
end)

describe("browser folding keys", function()
    it("cycles one note's body on tab, the cursor holding still", function()
        -- Org muscle memory: TAB on a headline folds and unfolds it, and
        -- moving the cursor is never part of the deal
        local source = project_buffer()
        annotate(source, 4, { "summary", "a body line" })
        local listing = assert(browser.open(source, { config = opts() }))
        vim.api.nvim_set_current_buf(listing)
        vim.api.nvim_win_set_cursor(0, { 1, 2 })
        assert.eq(vim.fn.foldclosed(1), -1, "the header is never folded")
        assert.eq(vim.fn.foldclosed(2), 2, "the prose opens shut")

        press("<Tab>")
        assert.eq(vim.fn.foldclosed(2), -1)
        assert.eq_deep(vim.api.nvim_win_get_cursor(0), { 1, 2 })

        press("<Tab>")
        assert.eq(vim.fn.foldclosed(2), 2)
    end)

    it("flips between the index and everything on shift-tab", function()
        local source = project_buffer()
        annotate(source, 1, { "first", "body" })
        annotate(source, 4, { "second", "body" })
        local listing = assert(browser.open(source, { config = opts() }))
        vim.api.nvim_set_current_buf(listing)

        press("<S-Tab>")
        assert.eq(vim.fn.foldclosed(2), -1, "every note opens from the index")
        press("<S-Tab>")
        assert.neq(vim.fn.foldclosed(2), -1, "and closes again from anything open")
    end)
end)

describe("browser cycling", function()
    ---Find the cursor column where the `name` header field starts.
    ---@param name string
    ---@return integer col 0-based
    local function column_of(name)
        local text = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
        local row = assert(require("sidenote.browser.parse").header(text))
        return row.fields[name].first - 1
    end

    it("cycles the kind when the cursor sits on its column", function()
        -- One pair of keys serves both fields: the column under the cursor
        -- decides, the way org rotates whatever point is on
        local source = project_buffer()
        local result = annotate(source, 4)
        vim.api.nvim_set_current_buf(assert(browser.open(source, { config = opts() })))
        vim.api.nvim_win_set_cursor(0, { 1, column_of("kind") })

        press("t")
        assert.eq(store.read(result.root, result.id).kind, "todo")
        assert.contains(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "todo")
        press("T")
        assert.eq(store.read(result.root, result.id).kind, "note")
    end)

    it("cycles the pen on its column, with the placeholder in the ring", function()
        -- The ring is `-` then the configured pens sorted by name, so a
        -- backward step from the first pen puts the pen back down
        local source = project_buffer()
        local result = annotate(source, 4)
        vim.api.nvim_set_current_buf(assert(browser.open(source, { config = opts() })))
        vim.api.nvim_win_set_cursor(0, { 1, column_of("pen") })

        press("t")
        assert.eq(store.read(result.root, result.id).pen, "blue")
        press("t")
        assert.eq(store.read(result.root, result.id).pen, "green")
        press("T")
        press("T")
        assert.is_nil(store.read(result.root, result.id).pen)
    end)

    it("holds still while it cycles: the open fold and cursor survive", function()
        -- The write rewrites the listing, but the user experiences a word
        -- changing under the cursor, not a screen redrawing
        local source = project_buffer()
        annotate(source, 4, { "summary", "a body line" })
        vim.api.nvim_set_current_buf(assert(browser.open(source, { config = opts() })))
        press("<Tab>")
        assert.eq(vim.fn.foldclosed(2), -1)
        local at = { 1, column_of("kind") }
        vim.api.nvim_win_set_cursor(0, at)

        press("t")
        assert.eq(vim.fn.foldclosed(2), -1, "the fold stays open")
        assert.eq_deep(vim.api.nvim_win_get_cursor(0), at, "the cursor stays put")
        press("t")
        assert.contains(
            vim.api.nvim_buf_get_lines(0, 0, 1, false)[1],
            "note",
            "still on kind, so the second press flips it back"
        )
    end)

    it("cycles the state everywhere else, wrapping at both ends", function()
        local source = project_buffer()
        local result = annotate(source, 4)
        vim.api.nvim_set_current_buf(assert(browser.open(source, { config = opts() })))
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        press("t")
        assert.eq(store.read(result.root, result.id).state, "resolved")
        press("T")
        assert.eq(store.read(result.root, result.id).state, "open")
        press("T")
        assert.eq(store.read(result.root, result.id).state, "archived")
    end)

    it("repaints the source buffer the moment a cycle writes", function()
        -- The listing edited the record out from under the code window; its
        -- ink follows now, not at the next save
        local source = project_buffer()
        local cfg = opts()
        cfg.indicator = { style = "highlight" }
        annotate(source, 4)
        session.refresh(source, cfg)

        vim.api.nvim_set_current_buf(assert(browser.open(source, { config = cfg })))
        vim.api.nvim_win_set_cursor(0, { 1, column_of("pen") })
        press("t")

        local marks = vim.api.nvim_buf_get_extmarks(source, render.NAMESPACE, 0, -1, {
            details = true,
        })
        local groups = {}
        for _, mark in ipairs(marks) do
            groups[mark[4].hl_group or ""] = true
        end
        assert.truthy(groups.SidenotePenBlue, "the pen's ink in the source")
    end)

    it("refuses to cycle over unsaved edits, which a repaint would eat", function()
        local source = project_buffer()
        local result = annotate(source, 4)
        local listing = assert(browser.open(source, { config = opts() }))
        vim.api.nvim_set_current_buf(listing)
        vim.api.nvim_buf_set_lines(listing, 1, 2, false, { "    an unsaved edit" })

        local messages = {}
        local original = vim.notify
        vim.notify = function(msg)
            messages[#messages + 1] = tostring(msg)
        end
        press("t")
        vim.notify = original

        assert.eq(store.read(result.root, result.id).kind, "note")
        local held = table.concat(vim.api.nvim_buf_get_lines(listing, 0, -1, false), "\n")
        assert.contains(held, "an unsaved edit", "the edit must survive")
        assert.contains(table.concat(messages, "\n"), "edits")
    end)
end)

describe("browser interactive filters", function()
    ---Answer the next vim.ui.select with `choice`, then run `fn`.
    ---@param choice string|nil
    ---@param fn fun()
    local function selecting(choice, fn)
        local original = vim.ui.select
        vim.ui.select = function(_, _, on_choice)
            on_choice(choice)
        end
        fn()
        vim.ui.select = original
    end

    it("narrows by kind from inside the listing, and widens back out", function()
        local source = project_buffer()
        annotate(source, 1)
        local result = annotate(source, 4)
        local rec = assert(store.read(result.root, result.id))
        rec.kind = "todo"
        assert(store.update(result.root, rec))

        local listing = assert(browser.open(source, { config = opts() }))
        vim.api.nvim_set_current_buf(listing)
        assert.eq(#assert(browser.state(listing)).rows, 2)

        selecting("todo", function()
            press("fk")
        end)
        assert.eq(#assert(browser.state(listing)).rows, 1)
        assert.eq(browser.state(listing).rows[1].entry.record.kind, "todo")

        selecting("(all)", function()
            press("fk")
        end)
        assert.eq(#assert(browser.state(listing)).rows, 2)
    end)

    it("clears every filter at once with fc", function()
        local source = project_buffer()
        annotate(source, 1)
        local listing =
            assert(browser.open(source, { config = opts(), filter = { kind = "todo" } }))
        vim.api.nvim_set_current_buf(listing)
        assert.eq(#assert(browser.state(listing)).rows, 0)

        press("fc")
        assert.eq(#assert(browser.state(listing)).rows, 1)
    end)

    it("narrows a project listing by path substring with ff", function()
        local source = project_buffer()
        annotate(source, 1)
        local name = vim.api.nvim_buf_get_name(source)
        local listing = assert(browser.open_project(name, { config = opts() }))
        vim.api.nvim_set_current_buf(listing)

        local original = vim.fn.input
        vim.fn.input = function()
            return "no-such-file"
        end
        press("ff")
        vim.fn.input = original

        assert.eq(#assert(browser.state(listing)).rows, 0)
    end)
end)

describe("browser cursor", function()
    ---Find the first column after the concealed marker on the listing's first line.
    ---@param listing integer
    ---@return integer col 0-indexed, as the cursor API counts
    local function visible_start(listing)
        local line = vim.api.nvim_buf_get_lines(listing, 0, 1, false)[1]
        return assert(line:match("^/%w+ ()")) - 1
    end

    it("keeps motions off the concealed id on a header line", function()
        local source = project_buffer()
        annotate(source, 1)
        local listing = assert(browser.open(source, { config = opts() }))
        local first = visible_start(listing)

        -- Headless runs never emit CursorMoved, so the motion is simulated:
        -- this exercises the registration and the clamp, not nvim's firing
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = listing })
        assert.eq(vim.api.nvim_win_get_cursor(0)[2], first, "0 lands on the kind column")

        vim.api.nvim_win_set_cursor(0, { 1, first - 1 })
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = listing })
        assert.eq(vim.api.nvim_win_get_cursor(0)[2], first, "h cannot walk into the marker")
    end)

    it("cannot break the marker by typing at the line's start", function()
        local source = project_buffer()
        annotate(source, 1)
        local listing = assert(browser.open(source, { config = opts() }))
        local first = visible_start(listing)

        press("0Ix<Esc>")
        local line = vim.api.nvim_buf_get_lines(listing, 0, 1, false)[1]
        assert.match(line, "^/%w+ ", "the id survived an insert at the line start")
        assert.eq(assert(line:match("^/%w+ ()")) - 1, first)
    end)

    it("snaps out of a closed fold's interior onto its top line", function()
        local source = project_buffer()
        annotate(source, 1, { "the summary", "the body", "more body" })
        local listing = assert(browser.open(source, { config = opts() }))

        -- A word motion over a closed fold strands the cursor in the hidden
        -- lines; headless never emits CursorMoved, so the landing is simulated
        vim.api.nvim_win_set_cursor(0, { 4, 5 })
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = listing })
        assert.eq_deep(vim.api.nvim_win_get_cursor(0), { 2, 0 })
    end)

    it("leaves the cursor alone on prose lines", function()
        local source = project_buffer()
        annotate(source, 1, { "the summary", "the body" })
        local listing = assert(browser.open(source, { config = opts() }))

        -- Open the fold so a prose line can hold the cursor at all
        press("zR")
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = listing })
        assert.eq(vim.api.nvim_win_get_cursor(0)[1], 2)
        assert.eq(vim.api.nvim_win_get_cursor(0)[2], 0, "prose owns its column 0")
    end)
end)

describe("browser help", function()
    it("answers g? with a float listing every browser mapping", function()
        local source = project_buffer()
        annotate(source, 4)
        assert(browser.open(source, { config = opts() }))

        press("g?")
        local winid = assert.not_nil(floating())
        local body = table.concat(
            vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(winid), 0, -1, false),
            "\n"
        )
        for _, key in ipairs({ "<CR>", "gf", "<Tab>", "-", "g?" }) do
            assert.contains(body, key)
        end
        assert.contains(body, "za")
        press("q")
    end)

    it("leaves ? meaning search, as everywhere else", function()
        local source = project_buffer()
        annotate(source, 4)
        assert(browser.open(source, { config = opts() }))

        assert.eq(vim.fn.maparg("?", "n"), "")
    end)

    it("closes the help again on q", function()
        local source = project_buffer()
        annotate(source, 4)
        assert(browser.open(source, { config = opts() }))

        press("g?")
        assert.not_nil(floating())
        press("q")
        assert.is_nil(floating())
    end)
end)
