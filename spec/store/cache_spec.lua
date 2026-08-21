local capture = require("sidenote.capture")
local index = require("sidenote.core.index")
local scan = require("sidenote.scan")
local store = require("sidenote.store")

---@param cache_dir? string omit to scan with caching off
---@return sidenote.Config
local function opts(cache_dir)
    return {
        filetype = "org",
        strategy = { "project" },
        project_dir = ".sidenote",
        global_dir = vim.fn.tempname(),
        cache_dir = cache_dir,
        indicator = { style = "sign" },
        preview = { style = "float", max_lines = 20 },
        editor = { style = "split", position = "right", size = 60 },
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---Build a project on disk with one annotation, through a discarded buffer.
---@return string root
---@return string id
local function project()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.sidenote", "p")
    local path = root .. "/m.lua"
    local fh = assert(io.open(path, "w"))
    fh:write(table.concat(SOURCE, "\n") .. "\n")
    fh:close()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, SOURCE)
    local result =
        assert(capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() }))
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return assert(vim.uv.fs_realpath(root)), result.id
end

---Rewrite the one cached resolution so a later hit is unmistakable.
---@param root string project root
---@param cfg sidenote.Config
---@param id string
local function poison(root, cfg, id)
    local path = assert(scan.cache_path(root .. "/.sidenote", cfg))
    local idx = index.load(path)
    local entry = assert(idx.entries[id], "nothing cached to poison")
    entry.resolution.line_start = 99
    entry.resolution.line_end = 99
    assert(index.save(path, idx))
end

describe("scan.project caching", function()
    it("writes a cache file once a scan resolves", function()
        local cache_dir = vim.fn.tempname()
        local root, id = project()
        scan.project({ path = root, config = opts(cache_dir) })

        local path = assert.not_nil(scan.cache_path(root .. "/.sidenote", opts(cache_dir)))
        assert.not_nil(index.load(path).entries[id])
    end)

    it("returns the cached resolution rather than resolving again", function()
        local cache_dir = vim.fn.tempname()
        local root, id = project()
        local cfg = opts(cache_dir)
        scan.project({ path = root, config = cfg })
        poison(root, cfg, id)

        local entries = scan.project({ path = root, config = cfg })
        assert.eq(entries[1].line_start, 99, "a fresh resolve would have said 4")
    end)

    it("ignores the cache once the record itself has changed", function()
        -- Records are edited in place, so a key carrying only the file
        -- hash would serve yesterday's answer for today's annotation
        local cache_dir = vim.fn.tempname()
        local root, id = project()
        local cfg = opts(cache_dir)
        scan.project({ path = root, config = cfg })
        poison(root, cfg, id)

        local rec = assert(store.read(root .. "/.sidenote", id))
        rec.kind = "todo"
        assert(store.update(root .. "/.sidenote", rec))

        local entries = scan.project({ path = root, config = cfg })
        assert.eq(entries[1].line_start, 4)
    end)

    it("ignores the cache once the file has changed", function()
        local cache_dir = vim.fn.tempname()
        local root, id = project()
        local cfg = opts(cache_dir)
        scan.project({ path = root, config = cfg })
        poison(root, cfg, id)

        local fh = assert(io.open(root .. "/m.lua", "w"))
        fh:write("-- moved\n" .. table.concat(SOURCE, "\n") .. "\n")
        fh:close()

        local entries = scan.project({ path = root, config = cfg })
        assert.eq(entries[1].line_start, 5)
    end)

    it("caches nothing when no cache directory is configured", function()
        local root = project()
        scan.project({ path = root, config = opts() })
        assert.is_nil(scan.cache_path(root .. "/.sidenote", opts()))
    end)
end)
