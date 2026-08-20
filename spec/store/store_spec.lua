local store = require("sidenote.store")
local record = require("sidenote.core.record")

---@return string
local function root()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    return dir
end

---@param over? table<string, any> fields overriding the fixture defaults
---@return sidenote.Annotation
local function rec(over)
    local base = {
        id = "01J9F3K2X7Q4V8M2ZC5T0BQWE",
        project_key = "demo-a3f91c",
        path = "lua/m.lua",
        scope = "lines",
        line_start = 1,
        line_end = 1,
        content = "local M = {}\nreturn M",
        now = "2026-08-18T09:14:00Z",
    }
    for key, value in pairs(over or {}) do
        base[key] = value
    end
    return record.capture(base)
end

describe("store.paths", function()
    it("suffixes metadata with .metadata.json", function()
        local paths = store.paths("/s", "abc", "org")
        assert.eq(paths.meta, "/s/abc.metadata.json")
        assert.eq(paths.prose, "/s/abc.org")
    end)

    it("keeps metadata distinct when prose is itself json", function()
        local paths = store.paths("/s", "abc", "json")
        assert.eq(paths.prose, "/s/abc.json")
        assert.neq(paths.prose, paths.meta)
    end)
end)

describe("store.create", function()
    it("writes both files of the pair", function()
        local dir = root()
        assert.truthy(store.create(dir, rec(), "org"))
        local paths = store.paths(dir, rec().id, "org")
        assert.not_nil(vim.uv.fs_stat(paths.meta))
        assert.not_nil(vim.uv.fs_stat(paths.prose))
    end)

    it("leaves the prose file empty for the user to fill", function()
        local dir = root()
        store.create(dir, rec(), "org")
        assert.eq(store.prose(dir, rec().id, "org"), "")
    end)

    it("creates the store directory when missing", function()
        local dir = root() .. "/nested/deeper"
        assert.truthy(store.create(dir, rec(), "org"))
        assert.not_nil(vim.uv.fs_stat(store.paths(dir, rec().id, "org").meta))
    end)

    it("refuses an invalid record", function()
        local bad = rec()
        bad.scope = "paragraph"
        local ok, err = store.create(root(), bad, "org")
        assert.eq(ok, false)
        assert.match(err, "scope")
    end)
end)

describe("store.read", function()
    it("round-trips a record", function()
        local dir = root()
        local original = rec()
        store.create(dir, original, "org")
        assert.eq_deep(store.read(dir, original.id), original)
    end)

    it("returns nil for an unknown id", function()
        assert.is_nil(store.read(root(), "nope"))
    end)

    it("returns an error for corrupt metadata rather than throwing", function()
        local dir = root()
        store.create(dir, rec(), "org")
        local fh = assert(io.open(store.paths(dir, rec().id, "org").meta, "w"))
        fh:write("{ not json")
        fh:close()
        local got, err = store.read(dir, rec().id)
        assert.is_nil(got)
        assert.is_type(err, "string")
    end)
end)

describe("store.update", function()
    it("persists a changed field", function()
        local dir = root()
        local original = rec()
        store.create(dir, original, "org")

        original.state = "resolved"
        assert.truthy(store.update(dir, original))
        assert.eq(store.read(dir, original.id).state, "resolved")
    end)

    it("cannot touch the prose file, even when it is read-only", function()
        -- Stronger than comparing mtimes: if update opened the prose file for
        -- writing it would fail outright, so success here proves it did not
        local dir = root()
        local original = rec()
        store.create(dir, original, "org")

        local prose_path = store.paths(dir, original.id, "org").prose
        local fh = assert(io.open(prose_path, "w"))
        fh:write("words the user wrote\n")
        fh:close()
        assert.truthy(vim.uv.fs_chmod(prose_path, 292)) -- 0444

        original.state = "resolved"
        local ok, err = store.update(dir, original)
        assert.truthy(ok, "update failed on a read-only prose file: " .. tostring(err))
        assert.eq(store.prose(dir, original.id, "org"), "words the user wrote\n")

        vim.uv.fs_chmod(prose_path, 420) -- 0644, so the temp dir can be cleaned
    end)

    it("refuses an invalid record", function()
        local dir = root()
        local original = rec()
        store.create(dir, original, "org")
        original.kind = "urgent"
        local ok, err = store.update(dir, original)
        assert.eq(ok, false)
        assert.match(err, "kind")
    end)
end)

describe("store.delete", function()
    it("removes both files of the pair", function()
        local dir = root()
        store.create(dir, rec(), "org")
        assert.truthy(store.delete(dir, rec().id, "org"))
        local paths = store.paths(dir, rec().id, "org")
        assert.is_nil(vim.uv.fs_stat(paths.meta))
        assert.is_nil(vim.uv.fs_stat(paths.prose))
    end)

    it("is false for an id that was never there", function()
        assert.eq(store.delete(root(), "nope", "org"), false)
    end)
end)

describe("store.prose_file", function()
    it("prefers the configured extension when it is there", function()
        local dir, annotation = root(), rec()
        store.create(dir, annotation, "org")
        assert.eq(
            store.prose_file(dir, annotation.id, "org"),
            store.prose_path(dir, annotation.id, "org")
        )
    end)

    it("falls back to whatever extension is actually on disk", function()
        -- A store written while `filetype` was org has to stay readable after
        -- that setting changes, and a headless run has no config at all
        local dir, annotation = root(), rec()
        store.create(dir, annotation, "org")
        assert.eq(
            store.prose_file(dir, annotation.id, "txt"),
            store.prose_path(dir, annotation.id, "org")
        )
    end)

    it("never mistakes the metadata sidecar for prose", function()
        local dir, annotation = root(), rec()
        store.create(dir, annotation, "json")
        assert.falsy(store.prose_file(dir, annotation.id, "md"):match("%.metadata%.json$"))
    end)

    it("is nil when the annotation has no prose file at all", function()
        local dir, annotation = root(), rec()
        store.update(dir, annotation)
        assert.is_nil(store.prose_file(dir, annotation.id, "txt"))
    end)

    it("reads prose through the extension on disk, not the one asked for", function()
        local dir, annotation = root(), rec()
        store.create(dir, annotation, "org")
        store.write_prose({ root = dir, id = annotation.id, filetype = "org", lines = { "hello" } })
        assert.eq(store.prose(dir, annotation.id, "txt"), "hello\n")
    end)

    it("writes prose into the file on disk, never a fork under a new extension", function()
        -- Reading falls back to the extension that exists; writing to the
        -- configured one instead would split the note across two files
        local dir, annotation = root(), rec()
        store.create(dir, annotation, "org")
        store.write_prose({ root = dir, id = annotation.id, filetype = "txt", lines = { "kept" } })
        assert.eq(store.prose(dir, annotation.id, "org"), "kept\n")
        assert.is_nil(vim.uv.fs_stat(store.prose_path(dir, annotation.id, "txt")))
    end)

    it("deletes the prose file whatever extension it carries", function()
        local dir, annotation = root(), rec()
        store.create(dir, annotation, "org")
        assert.truthy(store.delete(dir, annotation.id, "txt"))
        assert.is_nil(store.prose_file(dir, annotation.id, "org"))
    end)
end)
