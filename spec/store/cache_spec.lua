local fixture = require("spec.fixture")
local index = require("sidenote.core.index")
local scan = require("sidenote.scan")
local store = require("sidenote.store")

---@param cache_dir string where resolutions are cached
---@return sidenote.Config
local function opts(cache_dir)
    return fixture.opts({ cache_dir = cache_dir })
end

local SOURCE = fixture.SOURCE

---Build a project on disk with one annotation, through a discarded buffer.
---@return string root
---@return string id
local function project()
    local root = fixture.project({ ["m.lua"] = fixture.SOURCE })
    local note = fixture.annotate({
        path = root .. "/m.lua",
        line = 4,
        detach = true,
        config = opts(),
    })
    return root, note.id
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
