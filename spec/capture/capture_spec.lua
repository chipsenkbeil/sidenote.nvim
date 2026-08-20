local capture = require("sidenote.capture")
local store = require("sidenote.store")

---Build a project on disk with one source file, and open it in a buffer.
---
---The root is returned symlink-resolved, because that is what the capture path
---will compare against once the buffer name has been through the filesystem.
---@return integer bufnr
---@return string root
local function project_buffer()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.sidenote", "p")
    local path = root .. "/m.lua"
    local fh = assert(io.open(path, "w"))
    fh:write("local M = {}\n\nfunction M.f()\n  return 1\nend\n")
    fh:close()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "local M = {}",
        "",
        "function M.f()",
        "  return 1",
        "end",
    })
    return bufnr, assert(vim.uv.fs_realpath(root))
end

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

describe("capture.run", function()
    it("writes a sidecar pair into the project store", function()
        local bufnr, root = project_buffer()
        local result = assert.not_nil(
            capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })
        )
        assert.eq(result.root, root .. "/.sidenote")
        assert.not_nil(vim.uv.fs_stat(result.paths.meta))
        assert.not_nil(vim.uv.fs_stat(result.paths.prose))
    end)

    it("stores a path relative to the project root, not an absolute one", function()
        local bufnr = project_buffer()
        local result =
            capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })
        assert.eq(store.read(result.root, result.id).path, "m.lua")
    end)

    it("anchors the text that was actually selected", function()
        local bufnr = project_buffer()
        local result =
            capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })
        assert.eq(store.read(result.root, result.id).text, "  return 1")
    end)

    it("leaves the prose file empty for the user", function()
        local bufnr = project_buffer()
        local result =
            capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })
        assert.eq(store.prose(result.root, result.id, "org"), "")
    end)

    it("uses the configured filetype for the prose file", function()
        local bufnr = project_buffer()
        local result = capture.run(bufnr, { scope = "file", config = opts() })
        assert.match(result.paths.prose, "%.org$")
    end)

    it("captures a whole file with no anchor text", function()
        local bufnr = project_buffer()
        local result = capture.run(bufnr, { scope = "file", config = opts() })
        local rec = store.read(result.root, result.id)
        assert.eq(rec.scope, "file")
        assert.eq(rec.text, "")
    end)

    it("defaults the kind to note and carries todo when asked", function()
        local bufnr = project_buffer()
        local note = capture.run(bufnr, { scope = "file", config = opts() })
        local todo = capture.run(bufnr, { scope = "file", kind = "todo", config = opts() })
        assert.eq(store.read(note.root, note.id).kind, "note")
        assert.eq(store.read(todo.root, todo.id).kind, "todo")
    end)

    it("inks a fresh note with the active pen", function()
        local bufnr = project_buffer()
        local cfg = opts()
        cfg.pens = { coral = "SidenotePenCoral" }
        cfg.pen = "coral"

        local result = capture.run(bufnr, { scope = "file", config = cfg })
        assert.eq(store.read(result.root, result.id).pen, "coral")

        cfg.pen = nil
        local bare = capture.run(bufnr, { scope = "file", config = cfg })
        assert.is_nil(store.read(bare.root, bare.id).pen)
    end)

    it("inks each kind from its own default pen", function()
        local bufnr = project_buffer()
        local cfg = opts()
        cfg.pens = { coral = "SidenotePenCoral", blue = "SidenotePenBlue" }
        cfg.pen = { note = "blue", todo = "coral" }

        local note = capture.run(bufnr, { scope = "file", config = cfg })
        local todo = capture.run(bufnr, { scope = "file", kind = "todo", config = cfg })
        assert.eq(store.read(note.root, note.id).pen, "blue")
        assert.eq(store.read(todo.root, todo.id).pen, "coral")
    end)

    it("records vcs provenance as nil outside a repository", function()
        local bufnr = project_buffer()
        local result = capture.run(bufnr, { scope = "file", config = opts() })
        assert.is_nil(store.read(result.root, result.id).vcs)
    end)

    it("gives every capture a distinct id", function()
        local bufnr = project_buffer()
        local first = capture.run(bufnr, { scope = "file", config = opts() })
        local second = capture.run(bufnr, { scope = "file", config = opts() })
        assert.neq(first.id, second.id)
    end)

    it("stamps a UTC timestamp", function()
        local bufnr = project_buffer()
        local result = capture.run(bufnr, { scope = "file", config = opts() })
        assert.match(store.read(result.root, result.id).captured, "^%d%d%d%d%-%d%d%-%d%dT.*Z$")
    end)

    it("reports the store error when no strategy resolves", function()
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        local path = dir .. "/loose.lua"
        local fh = assert(io.open(path, "w"))
        fh:write("x = 1\n")
        fh:close()

        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(bufnr, path)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x = 1" })

        local result, err = capture.run(bufnr, { scope = "file", config = opts() })
        assert.is_nil(result)
        assert.contains(err, "no store resolved")
    end)

    it("reports the buffer error for an unnamed buffer", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local result, err = capture.run(bufnr, { scope = "file", config = opts() })
        assert.is_nil(result)
        assert.match(err, "name")
    end)
end)
