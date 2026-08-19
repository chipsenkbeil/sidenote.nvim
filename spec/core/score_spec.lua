local score = require("sidenote.core.score")
local record = require("sidenote.core.record")
local hash = require("sidenote.core.hash")

describe("score.similarity", function()
    it("is 1 for identical strings", function()
        assert.eq(score.similarity("abc", "abc"), 1)
    end)

    it("is 1 for strings differing only in surrounding whitespace", function()
        assert.eq(score.similarity("  abc ", "abc"), 1)
    end)

    it("is 0 for a comparison against empty", function()
        assert.eq(score.similarity("abc", ""), 0)
    end)

    it("is 1 for two empty strings", function()
        assert.eq(score.similarity("", ""), 1)
    end)

    it("is between 0 and 1 for a near match", function()
        local s = score.similarity("return a .. b", "return a .. c")
        assert.truthy(s > 0.8 and s < 1)
    end)

    it("short-circuits wildly different lengths to a low score", function()
        assert.lt(score.similarity("x", string.rep("y", 500)), 0.5)
    end)
end)

describe("score.candidate", function()
    it("returns 1 when every component matches exactly", function()
        assert.eq(score.candidate({ quote = 1, prefix = 1, suffix = 1, pos = 1 }), 1)
    end)

    it("returns 0 when nothing matches", function()
        assert.eq(score.candidate({ quote = 0, prefix = 0, suffix = 0, pos = 0 }), 0)
    end)

    it("weights the quote far above position", function()
        local quote_only = score.candidate({ quote = 1, prefix = 0, suffix = 0, pos = 0 })
        local pos_only = score.candidate({ quote = 0, prefix = 0, suffix = 0, pos = 1 })
        assert.gt(quote_only, pos_only * 10)
    end)
end)

describe("score.best", function()
    local ORIGINAL = table.concat({
        "local M = {}",
        "",
        "function M.join(a, b)",
        "  return a .. b",
        "end",
        "",
        "return M",
    }, "\n")

    ---@param content string
    ---@return sidenote.Annotation
    local function rec_for(content)
        return record.capture({
            id = "x",
            project_key = "demo",
            path = "m.lua",
            scope = "range",
            line_start = 3,
            line_end = 5,
            content = content,
            now = "2026-08-18T00:00:00Z",
        })
    end

    it("scores confidently when only the block changed and context survived", function()
        local rec = rec_for(ORIGINAL)
        local edited = table.concat({
            "local M = {}",
            "",
            "function M.join(a, b)",
            "  return a .. tostring(b)",
            "end",
            "",
            "return M",
        }, "\n")
        local hit = assert.not_nil(score.best(hash.split(edited), rec))
        assert.eq(hit.line_start, 3)
        assert.eq(hit.line_end, 5)
        assert.gt(hit.score, 0.8)
    end)

    it("finds the block but scores it mid-band when context also changed", function()
        -- Two independent edits, so landing between the guess and accept
        -- thresholds is the designed outcome rather than a defect
        local rec = rec_for(ORIGINAL)
        local moved = table.concat({
            "local M = {}",
            "local util = require('util')",
            "",
            "function M.join(a, b)",
            "  return a .. tostring(b)",
            "end",
            "",
            "return M",
        }, "\n")
        local hit = assert.not_nil(score.best(hash.split(moved), rec))
        assert.eq(hit.line_start, 4)
        assert.eq(hit.line_end, 6)
        assert.gt(hit.score, 0.6)
    end)

    it("grades context rather than treating it as all-or-nothing", function()
        -- Only the prefix differs, by one character versus entirely; a binary
        -- context hash scores both as 0 and cannot tell them apart
        local rec = rec_for(ORIGINAL)
        local function with_prefix(first)
            return table.concat({
                first,
                "",
                "function M.join(a, b)",
                "  return a .. b",
                "end",
                "",
                "return M",
            }, "\n")
        end
        local near = assert.not_nil(score.best(hash.split(with_prefix("local N = {}")), rec))
        local far = assert.not_nil(score.best(hash.split(with_prefix("print('nothing')")), rec))
        assert.gt(near.score, far.score)
    end)

    it("returns nil or a weak score when the block is gone entirely", function()
        local rec = rec_for(ORIGINAL)
        local hit = score.best(hash.split("local Q = {}\nreturn Q"), rec)
        assert.truthy(hit == nil or hit.score < 0.6)
    end)

    it("returns nil for a record with no anchor text", function()
        local rec = record.capture({
            id = "y",
            project_key = "demo",
            path = "m.lua",
            scope = "file",
            content = ORIGINAL,
            now = "2026-08-18T00:00:00Z",
        })
        assert.is_nil(score.best(hash.split(ORIGINAL), rec))
    end)
end)
