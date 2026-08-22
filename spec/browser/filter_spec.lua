local browser = require("sidenote.browser")
local fixture = require("spec.fixture")
local store = require("sidenote.store")

---@return sidenote.Config
local function opts()
    return fixture.opts({ browser = { style = "current" } })
end

local ALPHA = fixture.SOURCE
local BETA = fixture.SECOND

---@class spec.browser.Annotated
---@field root string project root on disk
---@field alpha integer buffer holding alpha.lua

---@return spec.browser.Annotated
local function annotated()
    local root = fixture.project({ ["alpha.lua"] = ALPHA, ["beta.lua"] = BETA })

    local alpha = vim.fn.bufadd(root .. "/alpha.lua")
    vim.fn.bufload(alpha)
    return { root = root, alpha = alpha }
end

---@class spec.browser.NoteOpts
---@field name string file to annotate, relative to the root
---@field line integer line to anchor on
---@field prose string[] the note itself
---@field kind? "note"|"todo" defaults to note
---@field state? "open"|"resolved"|"wontfix"|"archived" defaults to open

---@param root string
---@param note spec.browser.NoteOpts
---@return string id
local function annotate(root, note)
    return fixture.annotate({
        path = root .. "/" .. note.name,
        line = note.line,
        kind = note.kind,
        state = note.state,
        prose = note.prose,
        config = opts(),
    }).id
end

---@param bufnr integer
---@return string[]
local function summaries(bufnr)
    local out = {}
    for _, row in ipairs(assert(browser.state(bufnr)).rows) do
        out[#out + 1] = row.prose[1]
    end
    return out
end

---@return boolean
local function always_yes()
    return true
end

describe("filtering by provenance stamp", function()
    local filter = require("sidenote.filter")

    ---@param vcs sidenote.Vcs|nil
    ---@return sidenote.session.Entry
    local function stamped(vcs)
        return {
            status = "attached",
            record = { kind = "note", state = "open", path = "m.lua", vcs = vcs },
        }
    end

    it("keeps a note whose change id starts with the wanted prefix", function()
        local entry =
            stamped({ kind = "jj", commit = ("a"):rep(40), dirty = false, change = "zzowxyzq" })
        assert.eq(filter.survives(entry, { change = "zzo" }), true)
        assert.eq(filter.survives(entry, { change = "mn" }), false)
    end)

    it("drops an unstamped note when a change is wanted", function()
        assert.eq(filter.survives(stamped(nil), { change = "zzo" }), false)
    end)

    it("matches a commit prefix the same way", function()
        local entry = stamped({ kind = "git", commit = "abc123def", dirty = false })
        assert.eq(filter.survives(entry, { commit = "abc12" }), true)
        assert.eq(filter.survives(entry, { commit = "123" }), false)
    end)
end)

describe("browser filtering", function()
    it("keeps only the kind asked for", function()
        local t = annotated()
        annotate(t.root, { name = "alpha.lua", line = 1, prose = { "a note" } })
        annotate(t.root, { name = "alpha.lua", line = 4, prose = { "a todo" }, kind = "todo" })

        local bufnr = assert(browser.open(t.alpha, { config = opts(), filter = { kind = "todo" } }))
        assert.eq_deep(summaries(bufnr), { "a todo" })
    end)

    it("keeps only the lifecycle state asked for", function()
        local t = annotated()
        annotate(t.root, { name = "alpha.lua", line = 1, prose = { "still open" } })
        annotate(
            t.root,
            { name = "alpha.lua", line = 4, prose = { "given up on" }, state = "wontfix" }
        )

        local bufnr =
            assert(browser.open(t.alpha, { config = opts(), filter = { state = "wontfix" } }))
        assert.eq_deep(summaries(bufnr), { "given up on" })
    end)

    it("keeps only the anchor status asked for", function()
        local t = annotated()
        annotate(t.root, { name = "alpha.lua", line = 4, prose = { "still attached" } })
        annotate(t.root, { name = "beta.lua", line = 2, prose = { "about deleted code" } })

        os.remove(t.root .. "/beta.lua")
        vim.api.nvim_buf_delete(vim.fn.bufadd(t.root .. "/beta.lua"), { force = true })

        local bufnr = assert(
            browser.open_project(t.root, { config = opts(), filter = { status = "filegone" } })
        )
        assert.eq_deep(summaries(bufnr), { "about deleted code" })
    end)

    it("calls a deleted file still open in a buffer attached, not filegone", function()
        -- Resolution prefers a loaded buffer's text, so code you can still see
        -- on screen is not reported as gone just because the file was removed
        local t = annotated()
        annotate(t.root, { name = "beta.lua", line = 2, prose = { "about live code" } })
        os.remove(t.root .. "/beta.lua")

        local bufnr = assert(
            browser.open_project(t.root, { config = opts(), filter = { status = "attached" } })
        )
        assert.eq_deep(summaries(bufnr), { "about live code" })
    end)

    it("combines filters, keeping only rows that match all of them", function()
        local t = annotated()
        annotate(t.root, { name = "alpha.lua", line = 1, prose = { "open todo" }, kind = "todo" })
        annotate(t.root, {
            name = "alpha.lua",
            line = 4,
            prose = { "resolved todo" },
            kind = "todo",
            state = "resolved",
        })

        local filter = { kind = "todo", state = "resolved" }
        local bufnr = assert(browser.open(t.alpha, { config = opts(), filter = filter }))
        assert.eq_deep(summaries(bufnr), { "resolved todo" })
    end)

    it("shows everything when no filter is given", function()
        local t = annotated()
        annotate(t.root, { name = "alpha.lua", line = 1, prose = { "one" } })
        annotate(t.root, { name = "alpha.lua", line = 4, prose = { "two" }, kind = "todo" })

        local bufnr = assert(browser.open(t.alpha, { config = opts() }))
        assert.eq(#summaries(bufnr), 2)
    end)

    it("renders an empty listing when nothing matches, rather than failing", function()
        local t = annotated()
        annotate(t.root, { name = "alpha.lua", line = 1, prose = { "a note" } })

        local bufnr = assert(browser.open(t.alpha, { config = opts(), filter = { kind = "todo" } }))
        assert.eq_deep(summaries(bufnr), {})
        assert.eq_deep(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "" })
    end)

    it("narrows the listing you already have rather than opening a second", function()
        local t = annotated()
        annotate(t.root, { name = "alpha.lua", line = 1, prose = { "a note" } })
        annotate(t.root, { name = "alpha.lua", line = 4, prose = { "a todo" }, kind = "todo" })

        local all = assert(browser.open(t.alpha, { config = opts() }))
        local todos = assert(browser.open(t.alpha, { config = opts(), filter = { kind = "todo" } }))
        assert.eq(todos, all)
        assert.eq_deep(summaries(todos), { "a todo" })
    end)
end)

describe("browser filtering and the write path", function()
    it("never deletes an annotation the filter hid", function()
        -- The baseline is the filtered set, so a hidden row is not part of this
        -- listing's edits at all
        local t = annotated()
        local hidden = annotate(t.root, { name = "alpha.lua", line = 1, prose = { "a note" } })
        annotate(t.root, { name = "alpha.lua", line = 4, prose = { "a todo" }, kind = "todo" })

        local bufnr = assert(browser.open(t.alpha, { config = opts(), filter = { kind = "todo" } }))
        local root = assert(browser.state(bufnr)).rows[1].entry.root

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
        assert.eq(browser.write(bufnr, { confirm = always_yes }), 1)

        assert.truthy(vim.uv.fs_stat(store.meta_path(root, hidden)), "the hidden note survived")
    end)

    it("keeps the filter after a write re-renders", function()
        local t = annotated()
        annotate(t.root, { name = "alpha.lua", line = 1, prose = { "a note" } })
        annotate(t.root, { name = "alpha.lua", line = 4, prose = { "a todo" }, kind = "todo" })

        local bufnr = assert(browser.open(t.alpha, { config = opts(), filter = { kind = "todo" } }))
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        lines[2] = lines[2]:gsub("a todo$", "an edited todo")
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

        browser.write(bufnr, { confirm = always_yes })
        assert.eq_deep(summaries(bufnr), { "an edited todo" })
    end)
end)
