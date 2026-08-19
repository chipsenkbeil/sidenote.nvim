local capture = require("sidenote.capture")
local scan = require("sidenote.scan")

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

---Build a project with two annotatable files on disk.
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

---Annotate a file through a throwaway buffer, then discard it.
---
---The point of the scanner is that nothing needs to be loaded afterwards, so
---the buffer is deleted before anything is scanned.
---@param root string
---@param name string
---@param line integer
---@return string id
local function annotate(root, name, line)
    local path = root .. "/" .. name
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, path)
    local fh = assert(io.open(path, "r"))
    local body = fh:read("*a")
    fh:close()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(body:gsub("\n$", ""), "\n"))

    local result = assert(
        capture.run(bufnr, { scope = "lines", range = { line, 0, line, 0 }, config = opts() })
    )
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return result.id
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
        assert.contains(entries[1].root, ".annotations")
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
