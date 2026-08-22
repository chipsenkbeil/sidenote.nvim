local record = require("sidenote.core.record")
local store = require("sidenote.store")

---Make a fresh, empty store root.
---@return string
local function root()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    return dir
end

---Store an annotation on the first line of `path`.
---@param dir string store root to write into
---@param id string annotation id
---@param path string annotated file, relative to the project root
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
