local record = require("sidenote.core.record")
local hash = require("sidenote.core.hash")

local CONTENT = table.concat({
    "local M = {}", -- 1
    "", -- 2
    "function M.join(a, b)", -- 3
    "  return a .. b", -- 4
    "end", -- 5
    "", -- 6
    "return M", -- 7
}, "\n")

---@param over? table<string, any> fields overriding the fixture defaults
---@return sidenote.Annotation
local function capture(over)
    local opts = {
        id = "01J9F3K2X7Q4V8M2ZC5T0BQWE",
        project_key = "demo-a3f91c",
        path = "lua/m.lua",
        scope = "range",
        line_start = 3,
        line_end = 5,
        col_start = 1,
        col_end = 3,
        content = CONTENT,
        now = "2026-08-18T09:14:00Z",
    }
    for key, value in pairs(over or {}) do
        opts[key] = value
    end
    return record.capture(opts)
end

describe("record.capture", function()
    it("stores the anchor text verbatim", function()
        assert.eq(capture().text, "function M.join(a, b)\n  return a .. b\nend")
    end)

    it("defaults kind to note and state to open", function()
        local rec = capture()
        assert.eq(rec.kind, "note")
        assert.eq(rec.state, "open")
    end)

    it("stamps the current schema", function()
        assert.eq(capture().schema, record.SCHEMA)
    end)

    it("captures 3 lines of prefix and suffix context", function()
        local rec = capture()
        assert.eq(rec.prefix_sha, hash.sha256(hash.normalize("local M = {}\n")))
        assert.eq(rec.suffix_sha, hash.sha256(hash.normalize("\nreturn M")))
    end)

    it("hashes the whole file", function()
        assert.eq(capture().file_sha, hash.sha256(CONTENT))
    end)

    it("sets captured and verified to the same instant", function()
        local rec = capture()
        assert.eq(rec.captured, "2026-08-18T09:14:00Z")
        assert.eq(rec.verified, "2026-08-18T09:14:00Z")
    end)

    it("carries the project key so the record is self-describing", function()
        assert.eq(capture().project_key, "demo-a3f91c")
    end)

    it("represents a line annotation as a one-line range", function()
        local rec = capture({ scope = "lines", line_start = 4, line_end = 4 })
        assert.eq(rec.text, "  return a .. b")
        assert.eq(rec.line_start, 4)
        assert.eq(rec.line_end, 4)
    end)

    it("gives a line annotation no columns, since it covers whole lines", function()
        -- The location grammar derives scope from the presence of columns, so a
        -- non-zero column here would make `lines` render as `range`.
        local rec = capture({ scope = "lines", line_start = 4, line_end = 4 })
        assert.eq(rec.col_start, 0)
        assert.eq(rec.col_end, 0)
    end)

    it("represents a whole-file annotation with no text or position", function()
        local rec = capture({ scope = "file" })
        assert.eq(rec.scope, "file")
        assert.eq(rec.text, "")
        assert.eq(rec.line_start, 0)
        assert.eq(rec.line_end, 0)
    end)

    it("defaults vcs to nil rather than inventing one", function()
        assert.is_nil(capture().vcs)
    end)

    it("carries vcs provenance verbatim when given", function()
        local rec = capture({ vcs = { kind = "jj", commit = "7d248bfd", dirty = true } })
        assert.eq(rec.vcs.kind, "jj")
        assert.eq(rec.vcs.dirty, true)
    end)
end)

describe("record.validate", function()
    it("accepts a captured record", function()
        local ok, err = record.validate(capture())
        assert.eq(ok, true)
        assert.is_nil(err)
    end)

    it("rejects an unknown scope", function()
        local rec = capture()
        rec.scope = "paragraph"
        local ok, err = record.validate(rec)
        assert.eq(ok, false)
        assert.match(err, "scope")
    end)

    it("rejects an unknown kind", function()
        local rec = capture()
        rec.kind = "urgent"
        local ok, err = record.validate(rec)
        assert.eq(ok, false)
        assert.match(err, "kind")
    end)

    it("rejects an inverted line range", function()
        local rec = capture()
        rec.line_start, rec.line_end = 9, 2
        local ok, err = record.validate(rec)
        assert.eq(ok, false)
        assert.match(err, "line_end")
    end)

    it("rejects a zero line for a positioned scope", function()
        local rec = capture()
        rec.line_start, rec.line_end = 0, 0
        local ok, err = record.validate(rec)
        assert.eq(ok, false)
        assert.match(err, "line_start")
    end)

    it("rejects a missing id", function()
        local rec = capture()
        rec.id = nil
        local ok, err = record.validate(rec)
        assert.eq(ok, false)
        assert.match(err, "id")
    end)

    it("rejects a missing project key", function()
        local rec = capture()
        rec.project_key = nil
        local ok, err = record.validate(rec)
        assert.eq(ok, false)
        assert.match(err, "project_key")
    end)
end)

describe("record JSON round-trip", function()
    it("survives encode -> decode unchanged", function()
        local rec = capture()
        assert.eq_deep(record.decode(record.encode(rec)), rec)
    end)

    it("round-trips a record carrying vcs provenance", function()
        local rec = capture({ vcs = { kind = "git", commit = "abc123", dirty = false } })
        assert.eq_deep(record.decode(record.encode(rec)), rec)
    end)

    it("round-trips multi-line anchor text with quotes and backslashes", function()
        local tricky = 'local s = "he said \\"hi\\""\nlocal t = [[\nraw\n]]'
        local rec = capture({ content = tricky, line_start = 1, line_end = 4 })
        assert.eq_deep(record.decode(record.encode(rec)), rec)
    end)

    it("returns an error for malformed JSON rather than throwing", function()
        local rec, err = record.decode("{ not json")
        assert.is_nil(rec)
        assert.is_type(err, "string")
    end)

    it("returns an error for JSON that is not an object", function()
        local rec, err = record.decode("[1,2,3]")
        assert.is_nil(rec)
        assert.is_type(err, "string")
    end)
end)
