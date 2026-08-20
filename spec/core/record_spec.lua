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

    it("keeps the context verbatim, not only as a hash", function()
        -- The fuzzy tier grades context by similarity; a hash can only answer
        -- same-or-different, which zeroes the whole term on any edit above
        local rec = capture()
        assert.eq(rec.prefix, "local M = {}\n")
        assert.eq(rec.suffix, "\nreturn M")
    end)

    it("captures empty context at the very start of a file", function()
        local rec = capture({ scope = "lines", line_start = 1, line_end = 1 })
        assert.eq(rec.prefix, "")
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
        -- non-zero column here would make `lines` render as `range`
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

describe("record.reanchor", function()
    local LATER = "2026-09-01T12:00:00Z"

    ---@param over? table<string, any> fields overriding the re-anchor defaults
    ---@return sidenote.Annotation
    ---@return sidenote.Annotation original
    local function reanchor(over)
        local original = capture({ kind = "todo" })
        original.state = "wontfix"
        local opts = {
            path = "lua/m.lua",
            content = CONTENT,
            scope = "lines",
            line_start = 7,
            line_end = 7,
            now = LATER,
        }
        for key, value in pairs(over or {}) do
            opts[key] = value
        end
        return record.reanchor(original, opts), original
    end

    it("keeps the identity and the lifecycle the user owns", function()
        local fresh, original = reanchor()
        assert.eq(fresh.id, original.id)
        assert.eq(fresh.kind, "todo")
        assert.eq(fresh.state, "wontfix", "a re-anchor is not a fresh capture")
        assert.eq(fresh.project_key, original.project_key)
    end)

    it("keeps the original capture instant", function()
        -- The annotation did not stop existing; only its anchor moved
        local fresh, original = reanchor()
        assert.eq(fresh.captured, original.captured)
        assert.eq(fresh.verified, LATER)
    end)

    it("re-captures the anchor from the file as it is now", function()
        -- Not a search for the old text: editing a location asserts where the
        -- annotation belongs, which beats any resolver inference
        local fresh = reanchor()
        assert.eq(fresh.text, "return M")
        assert.eq(fresh.text_sha, hash.sha256("return M"))
        assert.eq(fresh.line_start, 7)
    end)

    it("refreshes the surrounding context, not only the anchor", function()
        local fresh, original = reanchor()
        assert.neq(fresh.prefix, original.prefix)
        assert.eq(fresh.prefix_sha, hash.sha256(hash.normalize(fresh.prefix)))
    end)

    it("empties the anchor when widening to file scope", function()
        local fresh = reanchor({ scope = "file" })
        assert.eq(fresh.text, "")
        assert.eq(fresh.line_start, 0)
        assert.eq(fresh.line_end, 0)
    end)

    it("keeps columns at zero outside range scope", function()
        -- A column here would make the grammar render `lines` as a range
        local fresh = reanchor()
        assert.eq(fresh.col_start, 0)
        assert.eq(fresh.col_end, 0)
    end)

    it("carries the anchor to a different file on a move", function()
        local other = "one\ntwo\nthree\n"
        local fresh = reanchor({
            path = "lua/other.lua",
            content = other,
            line_start = 2,
            line_end = 2,
        })
        assert.eq(fresh.path, "lua/other.lua")
        assert.eq(fresh.text, "two")
        assert.eq(fresh.file_sha, hash.sha256(other))
    end)

    it("produces a record the store will accept", function()
        assert.truthy(record.validate(reanchor()))
    end)
end)
