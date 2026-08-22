local export = require("sidenote.export")
local fixture = require("spec.fixture")

local STAMP = "2026-08-19T12:00:00Z"

local opts = fixture.opts

local ALPHA = fixture.SOURCE
local BETA = fixture.SECOND

---@return string root
local function project()
    return fixture.project({ ["alpha.lua"] = ALPHA, ["beta.lua"] = BETA })
end

---@class spec.agent.NoteOpts
---@field name string file to annotate, relative to the root
---@field line integer line to anchor on
---@field prose string[] the note itself

---@param root string
---@param note spec.agent.NoteOpts
---@return string id
local function annotate(root, note)
    return fixture.annotate({
        path = root .. "/" .. note.name,
        line = note.line,
        prose = note.prose,
        detach = true,
        config = opts(),
    }).id
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
        annotate(root, { name = "beta.lua", line = 3, prose = { "third" } })
        annotate(root, { name = "alpha.lua", line = 4, prose = { "second" } })
        annotate(root, { name = "alpha.lua", line = 1, prose = { "first" } })

        local doc = document(root)
        assert.eq(#doc.annotations, 3)
        assert.eq(doc.annotations[1].prose, "first")
        assert.eq(doc.annotations[2].prose, "second")
        assert.eq(doc.annotations[3].prose, "third")
    end)

    it("reports a deleted source file as code that no longer exists", function()
        local root = project()
        annotate(root, { name = "beta.lua", line = 2, prose = { "about deleted code" } })
        os.remove(root .. "/beta.lua")

        local record = document(root).annotations[1]
        assert.eq(record.status, "filegone")
        assert.truthy(record.code_no_longer_exists)
        assert.is_nil(record.line_start)
        assert.eq(record.anchor_text, "local x = 1")
    end)

    it("round-trips through vim.json unchanged", function()
        local root = project()
        annotate(root, { name = "alpha.lua", line = 4, prose = { "the note", "with a body" } })
        local doc = document(root)
        assert.eq_deep(vim.json.decode(vim.json.encode(doc)), doc)
    end)

    it("produces identical output for two runs over unchanged input", function()
        -- A reordering between runs would make the document undiffable
        local root = project()
        annotate(root, { name = "beta.lua", line = 3, prose = { "one" } })
        annotate(root, { name = "alpha.lua", line = 1, prose = { "two" } })
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
        annotate(
            root,
            { name = "alpha.lua", line = 4, prose = { "summary", "", "body after a gap" } }
        )
        assert.eq(document(root).annotations[1].prose, "summary\n\nbody after a gap")
    end)

    it("gives a note with no prose an empty string rather than nothing", function()
        local root = project()
        annotate(root, { name = "alpha.lua", line = 4, prose = {} })
        assert.eq(document(root).annotations[1].prose, "")
    end)
end)
