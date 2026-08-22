local fixture = require("spec.fixture")
local scan = require("sidenote.scan")

local opts = fixture.opts

local ALPHA = fixture.SOURCE
local BETA = fixture.SECOND

---@return string root
local function project()
    return fixture.project({ ["alpha.lua"] = ALPHA, ["beta.lua"] = BETA })
end

---@param root string
---@param name string
---@param line integer
---@return string id
local function annotate(root, name, line)
    return fixture.annotate({
        path = root .. "/" .. name,
        line = line,
        detach = true,
        config = opts(),
    }).id
end

describe("scan.project", function()
    it("finds annotations across every file in the project", function()
        local root = project()
        annotate(root, "alpha.lua", 4)
        annotate(root, "beta.lua", 2)

        local entries = scan.project({ path = root .. "/alpha.lua", config = opts() })
        assert.eq(#entries, 2)
    end)

    it("resolves against files on disk, with nothing loaded", function()
        local root = project()
        annotate(root, "alpha.lua", 4)

        local entries = scan.project({ path = root .. "/alpha.lua", config = opts() })
        assert.eq(entries[1].status, "attached")
        assert.eq(entries[1].line_start, 4)
    end)

    it("sorts by path and then by line, so two runs read the same", function()
        local root = project()
        annotate(root, "beta.lua", 3)
        annotate(root, "alpha.lua", 4)
        annotate(root, "alpha.lua", 1)

        local entries = scan.project({ path = root, config = opts() })
        assert.eq(entries[1].record.path, "alpha.lua")
        assert.eq(entries[1].line_start, 1)
        assert.eq(entries[2].record.path, "alpha.lua")
        assert.eq(entries[2].line_start, 4)
        assert.eq(entries[3].record.path, "beta.lua")
    end)

    it("accepts the project root itself, not only a file inside it", function()
        local root = project()
        annotate(root, "alpha.lua", 4)
        assert.eq(#scan.project({ path = root, config = opts() }), 1)
    end)

    it("resolves an untouched file at L0, straight off the file hash", function()
        -- Disk carries a trailing newline the buffer never shows; unless both
        -- flavors hash alike, the O(1) tier never fires for a headless run
        local root = project()
        annotate(root, "alpha.lua", 4)

        local entries = scan.project({ path = root, config = opts() })
        assert.eq(entries[1].resolution.tier, "L0")
    end)

    it("reports a deleted source file as filegone rather than skipping it", function()
        -- A note about code that no longer exists is exactly what a human needs
        -- to see
        local root = project()
        annotate(root, "beta.lua", 2)
        os.remove(root .. "/beta.lua")

        local entries = scan.project({ path = root, config = opts() })
        assert.eq(#entries, 1)
        assert.eq(entries[1].status, "filegone")
        assert.is_nil(entries[1].line_start)
    end)

    it("prefers a loaded buffer's text over what is on disk", function()
        -- So an interactive caller sees unsaved edits, while a headless one has
        -- no buffers and reads the file
        local root = project()
        annotate(root, "alpha.lua", 4)

        local bufnr = vim.fn.bufadd(root .. "/alpha.lua")
        vim.fn.bufload(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "-- inserted", "-- inserted" })

        local entries = scan.project({ path = root, config = opts() })
        assert.eq(entries[1].line_start, 6)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("carries the store root each annotation came from", function()
        local root = project()
        annotate(root, "alpha.lua", 4)
        local entries = scan.project({ path = root, config = opts() })
        assert.contains(entries[1].root, ".sidenote")
    end)

    it("yields an empty list for a project with no annotations", function()
        assert.eq_deep(scan.project({ path = project(), config = opts() }), {})
    end)

    it("yields an empty list rather than failing when no store resolves", function()
        local loose = vim.fn.tempname()
        vim.fn.mkdir(loose, "p")
        assert.eq_deep(scan.project({ path = loose, config = opts() }), {})
    end)

    it("reads each source file once however many notes target it", function()
        local root = project()
        for _, line in ipairs({ 1, 3, 4 }) do
            annotate(root, "alpha.lua", line)
        end
        local entries = scan.project({ path = root, config = opts() })
        assert.eq(#entries, 3)
        for _, entry in ipairs(entries) do
            assert.eq(entry.status, "attached")
        end
    end)
end)
