local browser = require("sidenote.browser")
local capture = require("sidenote.capture")
local store = require("sidenote.store")

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

local ALPHA = { "local M = {}", "", "function M.f()", "  return 1", "end" }
local BETA = { "-- beta", "local x = 1", "return x" }

---@class spec.browser.FilterTree
---@field root string project root on disk
---@field alpha integer buffer holding alpha.lua

---@return spec.browser.FilterTree
local function tree()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.sidenote", "p")
    for name, lines in pairs({ ["alpha.lua"] = ALPHA, ["beta.lua"] = BETA }) do
        local fh = assert(io.open(root .. "/" .. name, "w"))
        fh:write(table.concat(lines, "\n") .. "\n")
        fh:close()
    end
    root = assert(vim.uv.fs_realpath(root))

    local alpha = vim.fn.bufadd(root .. "/alpha.lua")
    vim.fn.bufload(alpha)
    return { root = root, alpha = alpha }
end

---@class spec.browser.NoteOpts
---@field name string file to annotate, relative to the root
---@field line integer line to anchor on
---@field prose string[] the note itself
---@field kind? "note"|"todo" defaults to note
---@field state? string lifecycle position to set afterwards

---@param root string
---@param note spec.browser.NoteOpts
---@return string id
local function annotate(root, note)
    local bufnr = vim.fn.bufadd(root .. "/" .. note.name)
    vim.fn.bufload(bufnr)

    local cfg = opts()
    local result = assert(capture.run(bufnr, {
        scope = "lines",
        range = { note.line, 0, note.line, 0 },
        kind = note.kind,
        config = cfg,
    }))

    local prose = assert(io.open(store.prose_path(result.root, result.id, cfg.filetype), "w"))
    prose:write(table.concat(note.prose, "\n") .. "\n")
    prose:close()

    if note.state then
        local rec = assert(store.read(result.root, result.id))
        rec.state = note.state
        store.update(result.root, rec)
    end
    return result.id
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

describe("browser filtering", function()
    it("keeps only the kind asked for", function()
        local t = tree()
        annotate(t.root, { name = "alpha.lua", line = 1, prose = { "a note" } })
        annotate(t.root, { name = "alpha.lua", line = 4, prose = { "a todo" }, kind = "todo" })

        local bufnr = assert(browser.open(t.alpha, { config = opts(), filter = { kind = "todo" } }))
        assert.eq_deep(summaries(bufnr), { "a todo" })
    end)

    it("keeps only the lifecycle state asked for", function()
        local t = tree()
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
        local t = tree()
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
        local t = tree()
        annotate(t.root, { name = "beta.lua", line = 2, prose = { "about live code" } })
        os.remove(t.root .. "/beta.lua")

        local bufnr = assert(
            browser.open_project(t.root, { config = opts(), filter = { status = "attached" } })
        )
        assert.eq_deep(summaries(bufnr), { "about live code" })
    end)

    it("combines filters, keeping only rows that match all of them", function()
        local t = tree()
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
        local t = tree()
        annotate(t.root, { name = "alpha.lua", line = 1, prose = { "one" } })
        annotate(t.root, { name = "alpha.lua", line = 4, prose = { "two" }, kind = "todo" })

        local bufnr = assert(browser.open(t.alpha, { config = opts() }))
        assert.eq(#summaries(bufnr), 2)
    end)

    it("renders an empty listing when nothing matches, rather than failing", function()
        local t = tree()
        annotate(t.root, { name = "alpha.lua", line = 1, prose = { "a note" } })

        local bufnr = assert(browser.open(t.alpha, { config = opts(), filter = { kind = "todo" } }))
        assert.eq_deep(summaries(bufnr), {})
        assert.eq_deep(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "" })
    end)

    it("narrows the listing you already have rather than opening a second", function()
        local t = tree()
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
        local t = tree()
        local hidden = annotate(t.root, { name = "alpha.lua", line = 1, prose = { "a note" } })
        annotate(t.root, { name = "alpha.lua", line = 4, prose = { "a todo" }, kind = "todo" })

        local bufnr = assert(browser.open(t.alpha, { config = opts(), filter = { kind = "todo" } }))
        local root = assert(browser.state(bufnr)).rows[1].entry.root

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
        assert.eq(
            browser.write(bufnr, {
                confirm = function()
                    return true
                end,
            }),
            1
        )

        assert.truthy(vim.uv.fs_stat(store.meta_path(root, hidden)), "the hidden note survived")
    end)

    it("keeps the filter after a write re-renders", function()
        local t = tree()
        annotate(t.root, { name = "alpha.lua", line = 1, prose = { "a note" } })
        annotate(t.root, { name = "alpha.lua", line = 4, prose = { "a todo" }, kind = "todo" })

        local bufnr = assert(browser.open(t.alpha, { config = opts(), filter = { kind = "todo" } }))
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        lines[2] = lines[2]:gsub("a todo$", "an edited todo")
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

        browser.write(bufnr, {
            confirm = function()
                return true
            end,
        })
        assert.eq_deep(summaries(bufnr), { "an edited todo" })
    end)
end)
