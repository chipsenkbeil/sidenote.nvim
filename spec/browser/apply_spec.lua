local apply = require("sidenote.browser.apply")
local browser = require("sidenote.browser")
local capture = require("sidenote.capture")
local diff = require("sidenote.browser.diff")
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

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }
local OTHER = { "-- other file", "local x = 1", "return x" }

---@class spec.browser.Project
---@field root string project root on disk
---@field source integer buffer holding the annotated file
---@field path string absolute path of the annotated file

---Build a project with one annotated source file and a sibling to move into.
---@return spec.browser.Project
local function project()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.sidenote", "p")

    for name, lines in pairs({ ["m.lua"] = SOURCE, ["other.lua"] = OTHER }) do
        local fh = assert(io.open(root .. "/" .. name, "w"))
        fh:write(table.concat(lines, "\n") .. "\n")
        fh:close()
    end

    local path = vim.uv.fs_realpath(root .. "/m.lua")
    local source = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(source, path)
    vim.api.nvim_buf_set_lines(source, 0, -1, false, SOURCE)
    return { root = root, source = source, path = path }
end

---@param source integer
---@param line integer
---@param prose string[]
---@return string id
local function annotate(source, line, prose)
    local cfg = opts()
    local result =
        assert(capture.run(source, { scope = "lines", range = { line, 0, line, 0 }, config = cfg }))
    local fh = assert(io.open(store.prose_path(result.root, result.id, cfg.filetype), "w"))
    fh:write(table.concat(prose, "\n") .. "\n")
    fh:close()
    return result.id
end

---Open the browser and hand back the state an edit is diffed against.
---@param source integer
---@return sidenote.browser.State
local function state_of(source)
    return assert(browser.state(assert(browser.open(source, { config = opts() }))))
end

---@param state sidenote.browser.State
---@param id string
---@return sidenote.Annotation
local function stored(state, id)
    for _, row in ipairs(state.rows) do
        if row.entry.id == id then
            return assert(store.read(row.entry.root, id))
        end
    end
    error("no such annotation: " .. id)
end

---@param state sidenote.browser.State
---@param id string
---@return string
local function root_of(state, id)
    for _, row in ipairs(state.rows) do
        if row.entry.id == id then
            return row.entry.root
        end
    end
    error("no such annotation: " .. id)
end

---Edit the browser's own lines and diff them, which is what :w does.
---@param state sidenote.browser.State
---@param edited string[]
---@return sidenote.browser.Action[]
local function actions_from(state, edited)
    local parse = require("sidenote.browser.parse")
    local rows, errors = parse.buffer(edited)
    assert.eq_deep(errors, {}, "the edited buffer did not parse")
    return diff.compute(state, rows)
end

describe("browser.apply.validate", function()
    it("rejects a move into a file that does not exist", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)
        local action =
            { kind = "move", id = id, lnum = 1, lossy = false, to = "lua/nope.lua:1", from = "" }

        local errors = apply.validate({ action }, state)
        assert.eq(#errors, 1)
        assert.contains(errors[1].message, "nope.lua")
    end)

    it("rejects a line past the end of the file, naming the real count", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)
        local action =
            { kind = "rescope", id = id, lnum = 1, lossy = false, to = "m.lua:99", from = "" }

        local errors = apply.validate({ action }, state)
        assert.eq(#errors, 1)
        assert.contains(errors[1].message, "5")
    end)

    it("reports an error against the line its row came from", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)
        local action =
            { kind = "rescope", id = id, lnum = 7, lossy = false, to = "m.lua:99", from = "" }
        assert.eq(apply.validate({ action }, state)[1].lnum, 7)
    end)

    it("refuses to write prose that is open and modified in another buffer", function()
        -- Rather than racing that buffer and losing whichever write lands last
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)

        local prose_path = store.prose_path(root_of(state, id), id, opts().filetype)
        local prose_buf = vim.fn.bufadd(prose_path)
        vim.fn.bufload(prose_buf)
        vim.api.nvim_buf_set_lines(prose_buf, 0, -1, false, { "edited elsewhere" })

        local action = { kind = "write", id = id, lnum = 1, lossy = false, prose = { "from here" } }
        local errors = apply.validate({ action }, state)
        assert.eq(#errors, 1)
        assert.contains(errors[1].message, "open")
        vim.bo[prose_buf].modified = false
    end)

    it("passes a set of actions that are all possible", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)
        local actions = {
            { kind = "write", id = id, lnum = 1, lossy = false, prose = { "rewritten" } },
            { kind = "rescope", id = id, lnum = 1, lossy = false, to = "m.lua:2", from = "" },
        }
        assert.eq_deep(apply.validate(actions, state), {})
    end)
end)

describe("browser.apply.run", function()
    it("deletes both sidecar files", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)
        local root = root_of(state, id)

        local applied, failures = apply.run({ { kind = "delete", id = id, lossy = true } }, state)
        assert.eq(applied, 1)
        assert.eq_deep(failures, {})
        assert.falsy(vim.uv.fs_stat(store.meta_path(root, id)))
        assert.falsy(vim.uv.fs_stat(store.prose_path(root, id, opts().filetype)))
    end)

    it("writes metadata only for a change, even when the prose file is read-only", function()
        -- The ownership boundary is physical: a change never opens prose
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)
        vim.fn.setfperm(store.prose_path(root_of(state, id), id, opts().filetype), "r--r--r--")

        local action =
            { kind = "change", id = id, lossy = false, field = "kind", from = "note", to = "todo" }
        assert.eq(apply.run({ action }, state), 1)
        assert.eq(stored(state, id).kind, "todo")
    end)

    it("changes state without disturbing kind", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)
        local action = {
            kind = "change",
            id = id,
            lossy = false,
            field = "state",
            from = "open",
            to = "wontfix",
        }
        assert.eq(apply.run({ action }, state), 1)
        assert.eq(stored(state, id).state, "wontfix")
        assert.eq(stored(state, id).kind, "note")
    end)

    it("rewrites prose on a write, leaving the record alone", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)
        local before = stored(state, id)

        local action =
            { kind = "write", id = id, lossy = false, prose = { "a new summary", "and a body" } }
        assert.eq(apply.run({ action }, state), 1)

        local root = root_of(state, id)
        assert.eq(store.prose(root, id, opts().filetype), "a new summary\nand a body\n")
        assert.eq_deep(stored(state, id), before)
    end)

    it("re-anchors a rescope against the file as it is now", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)

        local action =
            { kind = "rescope", id = id, lossy = false, from = "m.lua:4", to = "m.lua:1" }
        assert.eq(apply.run({ action }, state), 1)

        local rec = stored(state, id)
        assert.eq(rec.line_start, 1)
        assert.eq(rec.text, "local M = {}", "the anchor is taken from the asserted location")
    end)

    it("drops the anchor when a rescope widens to file scope", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)

        local action = { kind = "rescope", id = id, lossy = true, from = "m.lua:4", to = "m.lua" }
        assert.eq(apply.run({ action }, state), 1)

        local rec = stored(state, id)
        assert.eq(rec.scope, "file")
        assert.eq(rec.text, "")
        assert.eq(rec.line_start, 0)
    end)

    it("re-anchors a move against the destination's content", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)

        local action =
            { kind = "move", id = id, lossy = false, from = "m.lua:4", to = "other.lua:2" }
        assert.eq(apply.run({ action }, state), 1)

        local rec = stored(state, id)
        assert.eq(rec.path, "other.lua")
        assert.eq(rec.text, "local x = 1")
    end)

    it("keeps kind, state and the capture instant across a re-anchor", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)
        local before = stored(state, id)

        local change = {
            kind = "change",
            id = id,
            lossy = false,
            field = "state",
            from = "open",
            to = "wontfix",
        }
        local move = { kind = "rescope", id = id, lossy = false, from = "m.lua:4", to = "m.lua:1" }
        assert.eq(apply.run({ change, move }, state), 2)

        local rec = stored(state, id)
        assert.eq(rec.state, "wontfix", "an earlier change in the same pass is not undone")
        assert.eq(rec.captured, before.captured)
    end)

    it("reports a failing action without abandoning the rest", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local state = state_of(p.source)
        local actions = {
            { kind = "delete", id = "01NOTAREALIDNOTAREALIDXXXX", lossy = true },
            { kind = "write", id = id, lossy = false, prose = { "still written" } },
        }

        local applied, failures = apply.run(actions, state)
        assert.eq(applied, 1)
        assert.eq(#failures, 1)
        assert.eq(store.prose(root_of(state, id), id, opts().filetype), "still written\n")
    end)
end)

describe("browser edit to action, end to end", function()
    it("turns a deleted closed row into a delete of that annotation", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note", "with a body" })
        local state = state_of(p.source)

        local actions = actions_from(state, {})
        assert.eq(#actions, 1)
        assert.eq(actions[1].kind, "delete")
        assert.eq(actions[1].id, id)

        assert.eq(apply.run(actions, state), 1)
        assert.falsy(vim.uv.fs_stat(store.meta_path(root_of(state, id), id)))
    end)

    it("turns an edited summary into prose on disk", function()
        local p = project()
        local id = annotate(p.source, 4, { "the note" })
        local bufnr = assert(browser.open(p.source, { config = opts() }))
        local state = assert(browser.state(bufnr))

        local edited = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        edited[2] = edited[2]:gsub("the note$", "a better summary")

        local actions = actions_from(state, edited)
        assert.eq(#actions, 1)
        assert.eq(actions[1].kind, "write")
        assert.eq(apply.run(actions, state), 1)
        assert.eq(store.prose(root_of(state, id), id, opts().filetype), "a better summary\n")
    end)
end)
