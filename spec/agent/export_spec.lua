local capture = require("sidenote.capture")
local export = require("sidenote.export")
local store = require("sidenote.store")

local STAMP = "2026-08-19T12:00:00Z"

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

---@return string root
local function project()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.annotations", "p")
    for name, lines in pairs({ ["alpha.lua"] = ALPHA, ["beta.lua"] = BETA }) do
        local fh = assert(io.open(root .. "/" .. name, "w"))
        fh:write(table.concat(lines, "\n") .. "\n")
        fh:close()
    end
    return assert(vim.uv.fs_realpath(root))
end

---@param root string
---@param name string
---@param line integer
---@param prose string[]
---@return string id
local function annotate(root, name, line, prose)
    local path = root .. "/" .. name
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, path)
    local fh = assert(io.open(path, "r"))
    local body = fh:read("*a")
    fh:close()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(body:gsub("\n$", ""), "\n"))

    local cfg = opts()
    local result =
        assert(capture.run(bufnr, { scope = "lines", range = { line, 0, line, 0 }, config = cfg }))
    vim.api.nvim_buf_delete(bufnr, { force = true })

    local note = assert(io.open(store.prose_path(result.root, result.id, cfg.filetype), "w"))
    note:write(table.concat(prose, "\n") .. "\n")
    note:close()
    return result.id
end

---@param root string
---@return sidenote.export.Document
local function document(root)
    return export.project({ path = root, config = opts(), now = STAMP })
end

describe("export.project", function()
    it("stamps the document with a schema and the project it describes", function()
        local root = project()
        local doc = document(root)
        assert.eq(doc.schema, export.SCHEMA)
        assert.eq(doc.generated, STAMP)
        assert.contains(doc.project_key, vim.fn.fnamemodify(root, ":t"))
    end)

    it("groups annotations from several files, sorted by path then line", function()
        local root = project()
        annotate(root, "beta.lua", 3, { "third" })
        annotate(root, "alpha.lua", 4, { "second" })
        annotate(root, "alpha.lua", 1, { "first" })

        local doc = document(root)
        assert.eq(#doc.annotations, 3)
        assert.eq(doc.annotations[1].prose, "first")
        assert.eq(doc.annotations[2].prose, "second")
        assert.eq(doc.annotations[3].prose, "third")
    end)

    it("reports a deleted source file as code that no longer exists", function()
        local root = project()
        annotate(root, "beta.lua", 2, { "about deleted code" })
        os.remove(root .. "/beta.lua")

        local record = document(root).annotations[1]
        assert.eq(record.status, "filegone")
        assert.truthy(record.code_no_longer_exists)
        assert.is_nil(record.line_start)
        assert.eq(record.anchor_text, "local x = 1")
    end)

    it("round-trips through vim.json unchanged", function()
        local root = project()
        annotate(root, "alpha.lua", 4, { "the note", "with a body" })
        local doc = document(root)
        assert.eq_deep(vim.json.decode(vim.json.encode(doc)), doc)
    end)

    it("produces identical output for two runs over unchanged input", function()
        -- The document is meant to be diffable; a reordering between runs would
        -- make every diff meaningless
        local root = project()
        annotate(root, "beta.lua", 3, { "one" })
        annotate(root, "alpha.lua", 1, { "two" })
        assert.eq(vim.json.encode(document(root)), vim.json.encode(document(root)))
    end)

    it("yields an empty annotation list rather than failing on an empty store", function()
        local doc = document(project())
        assert.eq_deep(doc.annotations, {})
        assert.eq(doc.schema, export.SCHEMA)
    end)

    it("encodes an empty annotation list as a JSON array, not an object", function()
        -- An agent iterating the field must not have to special-case {}
        assert.contains(vim.json.encode(document(project())), '"annotations":[]')
    end)

    it("carries prose with its trailing newline trimmed but its shape intact", function()
        local root = project()
        annotate(root, "alpha.lua", 4, { "summary", "", "body after a gap" })
        assert.eq(document(root).annotations[1].prose, "summary\n\nbody after a gap")
    end)

    it("gives a note with no prose an empty string rather than nothing", function()
        local root = project()
        annotate(root, "alpha.lua", 4, {})
        assert.eq(document(root).annotations[1].prose, "")
    end)
end)
