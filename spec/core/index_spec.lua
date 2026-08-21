local index = require("sidenote.core.index")

local RESOLUTION = {
    status = "attached",
    tier = "L2",
    line_start = 5,
    line_end = 7,
    confidence = 1,
}

---@return string
local function tmpfile()
    return vim.fn.tempname() .. ".json"
end

describe("index round-trip", function()
    it("returns what was put, for the same content hash", function()
        local idx = index.new()
        index.put(idx, "id1", { against = "sha-a", resolution = RESOLUTION })
        local got = index.get(idx, "id1", "sha-a")
        assert.eq(got.status, "attached")
        assert.eq(got.line_start, 5)
    end)

    it("returns nil when the file content has changed", function()
        local idx = index.new()
        index.put(idx, "id1", { against = "sha-a", resolution = RESOLUTION })
        assert.is_nil(index.get(idx, "id1", "sha-b"))
    end)

    it("returns nil for an unknown id", function()
        assert.is_nil(index.get(index.new(), "nope", "sha-a"))
    end)

    it("survives save and load", function()
        local path = tmpfile()
        local idx = index.new()
        index.put(idx, "id1", { against = "sha-a", resolution = RESOLUTION })
        assert.truthy(index.save(path, idx))

        local got = index.get(index.load(path), "id1", "sha-a")
        assert.eq(got.status, "attached")
        assert.eq(got.line_end, 7)
    end)
end)

describe("index resilience", function()
    it("returns an empty index for a missing file", function()
        local idx = index.load("/nonexistent/path/index.json")
        assert.eq(idx.version, index.VERSION)
        assert.eq_deep(idx.entries, {})
    end)

    it("discards a corrupt file rather than erroring", function()
        local path = tmpfile()
        local fh = assert(io.open(path, "w"))
        fh:write("{ this is not json")
        fh:close()
        assert.eq_deep(index.load(path).entries, {})
    end)

    it("discards an index written by a different version", function()
        local path = tmpfile()
        local fh = assert(io.open(path, "w"))
        fh:write(vim.json.encode({ version = 999, entries = { id1 = { against = "x" } } }))
        fh:close()
        assert.eq_deep(index.load(path).entries, {})
    end)
end)

describe("index by_path", function()
    it("returns an empty list for an untracked path", function()
        assert.eq_deep(index.ids_for(index.new(), "lua/m.lua"), {})
    end)

    it("tracks several ids for one source file", function()
        local idx = index.new()
        index.track(idx, "lua/m.lua", "id1")
        index.track(idx, "lua/m.lua", "id2")
        assert.eq_deep(index.ids_for(idx, "lua/m.lua"), { "id1", "id2" })
    end)

    it("does not duplicate an id tracked twice", function()
        local idx = index.new()
        index.track(idx, "lua/m.lua", "id1")
        index.track(idx, "lua/m.lua", "id1")
        assert.eq_deep(index.ids_for(idx, "lua/m.lua"), { "id1" })
    end)

    it("keeps paths independent", function()
        local idx = index.new()
        index.track(idx, "lua/a.lua", "id1")
        index.track(idx, "lua/b.lua", "id2")
        assert.eq_deep(index.ids_for(idx, "lua/a.lua"), { "id1" })
        assert.eq_deep(index.ids_for(idx, "lua/b.lua"), { "id2" })
    end)

    it("untracks one id without disturbing the others", function()
        local idx = index.new()
        index.track(idx, "lua/m.lua", "id1")
        index.track(idx, "lua/m.lua", "id2")
        index.untrack(idx, "lua/m.lua", "id1")
        assert.eq_deep(index.ids_for(idx, "lua/m.lua"), { "id2" })
    end)

    it("drops the path entirely once its last id is untracked", function()
        local idx = index.new()
        index.track(idx, "lua/m.lua", "id1")
        index.untrack(idx, "lua/m.lua", "id1")
        assert.eq_deep(index.ids_for(idx, "lua/m.lua"), {})
        assert.is_nil(idx.by_path["lua/m.lua"])
    end)

    it("survives save and load", function()
        local path = tmpfile()
        local idx = index.new()
        index.track(idx, "lua/m.lua", "id1")
        assert.truthy(index.save(path, idx))
        assert.eq_deep(index.ids_for(index.load(path), "lua/m.lua"), { "id1" })
    end)

    it("heals an index written before by_path existed", function()
        local path = tmpfile()
        local fh = assert(io.open(path, "w"))
        fh:write(vim.json.encode({
            version = index.VERSION,
            entries = { id1 = { against = "sha-a", resolution = RESOLUTION } },
        }))
        fh:close()

        local idx = index.load(path)
        assert.eq_deep(idx.by_path, {})
        assert.eq(index.get(idx, "id1", "sha-a").status, "attached")
    end)
end)
