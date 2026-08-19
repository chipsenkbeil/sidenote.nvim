local store = require("sidenote.store")
local record = require("sidenote.core.record")
local index = require("sidenote.core.index")

---@return string
local function root()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    return dir
end

---@param dir string
---@param id string
---@param path string
local function put(dir, id, path)
    store.create(
        dir,
        record.capture({
            id = id,
            project_key = "demo",
            path = path,
            scope = "lines",
            line_start = 1,
            line_end = 1,
            content = "local M = {}",
            now = "2026-08-18T09:14:00Z",
        }),
        "org"
    )
end

describe("store.ids", function()
    it("is empty for an empty root", function()
        assert.eq_deep(store.ids(root()), {})
    end)

    it("is empty for a root that does not exist", function()
        assert.eq_deep(store.ids("/nonexistent/store"), {})
    end)

    it("lists every annotation, sorted", function()
        local dir = root()
        put(dir, "01B", "a.lua")
        put(dir, "01A", "a.lua")
        assert.eq_deep(store.ids(dir), { "01A", "01B" })
    end)

    it("ignores the prose files and the index", function()
        local dir = root()
        put(dir, "01A", "a.lua")
        local fh = assert(io.open(dir .. "/index.json", "w"))
        fh:write("{}")
        fh:close()
        assert.eq_deep(store.ids(dir), { "01A" })
    end)
end)

describe("store.rebuild", function()
    it("groups annotation ids by source path", function()
        local dir = root()
        put(dir, "01A", "a.lua")
        put(dir, "01B", "a.lua")
        put(dir, "01C", "b.lua")

        local idx = store.rebuild({ dir })
        assert.eq_deep(index.ids_for(idx, "a.lua"), { "01A", "01B" })
        assert.eq_deep(index.ids_for(idx, "b.lua"), { "01C" })
    end)

    it("unions several roots", function()
        local a, b = root(), root()
        put(a, "01A", "a.lua")
        put(b, "01B", "b.lua")

        local idx = store.rebuild({ a, b })
        assert.eq_deep(index.ids_for(idx, "a.lua"), { "01A" })
        assert.eq_deep(index.ids_for(idx, "b.lua"), { "01B" })
    end)

    it("lets an earlier root win on an id conflict", function()
        local a, b = root(), root()
        put(a, "01A", "first.lua")
        put(b, "01A", "second.lua")

        local idx = store.rebuild({ a, b })
        assert.eq_deep(index.ids_for(idx, "first.lua"), { "01A" })
        assert.eq_deep(index.ids_for(idx, "second.lua"), {})
    end)

    it("skips corrupt metadata without failing the whole rebuild", function()
        local dir = root()
        put(dir, "01A", "a.lua")
        local fh = assert(io.open(dir .. "/01BAD.metadata.json", "w"))
        fh:write("{ not json")
        fh:close()

        assert.eq_deep(index.ids_for(store.rebuild({ dir }), "a.lua"), { "01A" })
    end)

    it("produces an index a fresh process can use as a cache", function()
        local dir = root()
        put(dir, "01A", "a.lua")
        local path = dir .. "/index.json"
        assert.truthy(index.save(path, store.rebuild({ dir })))
        assert.eq_deep(index.ids_for(index.load(path), "a.lua"), { "01A" })
    end)
end)
