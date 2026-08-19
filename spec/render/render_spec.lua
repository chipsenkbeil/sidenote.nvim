local render = require("sidenote.render")
local highlight = require("sidenote.highlight")

---@param lines string[]
---@return integer
local function scratch(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
end

local LINES = { "one", "two", "three", "four", "five" }

---@param bufnr integer
---@return table[]
local function marks(bufnr)
    return vim.api.nvim_buf_get_extmarks(bufnr, render.NAMESPACE, 0, -1, { details = true })
end

describe("render.paint", function()
    it("places one mark per entry", function()
        local bufnr = scratch(LINES)
        local placed = render.paint(bufnr, {
            { id = "a", status = "attached", line_start = 2, line_end = 2 },
            { id = "b", status = "orphaned", line_start = 4, line_end = 5 },
        }, { style = "sign" })
        assert.eq(placed, 2)
        assert.eq(#marks(bufnr), 2)
    end)

    it("converts 1-indexed lines to 0-indexed rows exactly once", function()
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 2, line_end = 2 } },
            { style = "sign" }
        )
        assert.eq(marks(bufnr)[1][2], 1)
    end)

    it("styles the mark by status", function()
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "orphaned", line_start = 1, line_end = 1 } },
            { style = "sign" }
        )
        assert.eq(marks(bufnr)[1][4].sign_hl_group, highlight.GROUPS.orphaned)
    end)

    it("skips an entry with no position, since there is nothing to point at", function()
        local bufnr = scratch(LINES)
        local placed = render.paint(
            bufnr,
            { { id = "a", status = "orphaned" } },
            { style = "sign" }
        )
        assert.eq(placed, 0)
        assert.eq(#marks(bufnr), 0)
    end)

    it("skips an entry past the end of the buffer rather than clamping it", function()
        -- Clamping is how an annotation silently ends up on unrelated code
        local bufnr = scratch(LINES)
        local placed = render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 99, line_end = 99 } },
            { style = "sign" }
        )
        assert.eq(placed, 0)
    end)

    it("places nothing at all when the style is none", function()
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 1, line_end = 1 } },
            { style = "none" }
        )
        assert.eq(#marks(bufnr), 0)
    end)

    it("highlights the whole range when the style is highlight", function()
        -- The extmark end is exclusive, so covering lines 2 through 4 means
        -- ending at row 4; ending at row 3 leaves the last line unmarked
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 2, line_end = 4 } },
            { style = "highlight" }
        )
        assert.eq(marks(bufnr)[1][2], 1)
        assert.eq(marks(bufnr)[1][4].end_row, 4)
    end)

    it("puts the sign at end of line when the style is virt_text", function()
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 1, line_end = 1 } },
            { style = "virt_text" }
        )
        assert.eq(marks(bufnr)[1][4].virt_text[1][2], highlight.GROUPS.attached)
    end)
end)

describe("render.clear", function()
    it("removes every mark it placed", function()
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 1, line_end = 1 } },
            { style = "sign" }
        )
        render.clear(bufnr)
        assert.eq(#marks(bufnr), 0)
    end)

    it("is safe on a buffer that was never painted", function()
        render.clear(scratch(LINES))
    end)
end)

describe("render repaint", function()
    it("does not accumulate marks across repaints", function()
        local bufnr = scratch(LINES)
        local entries = { { id = "a", status = "attached", line_start = 1, line_end = 1 } }
        render.paint(bufnr, entries, { style = "sign" })
        render.paint(bufnr, entries, { style = "sign" })
        assert.eq(#marks(bufnr), 1)
    end)
end)

describe("render.paint span styles", function()
    it("gives underline a different look from highlight", function()
        -- They were the same mark, so the option did nothing
        local bufnr = scratch(LINES)
        local entries = { { id = "1", status = "attached", line_start = 2, line_end = 2 } }

        render.paint(bufnr, entries, { style = "highlight" })
        local highlighted = marks(bufnr)[1][4]
        render.paint(bufnr, entries, { style = "underline" })
        local underlined = marks(bufnr)[1][4]

        assert.neq(underlined.hl_group, highlighted.hl_group)
        assert.falsy(underlined.hl_eol, "an underline belongs under the text, not past it")
        assert.truthy(highlighted.hl_eol)
    end)

    it("underlines through a group linked to the diagnostic underline family", function()
        highlight.setup()
        for status, group in pairs(highlight.UNDERLINES) do
            local hl = vim.api.nvim_get_hl(0, { name = group, link = true })
            assert.match(
                hl.link,
                "^DiagnosticUnderline",
                status .. " links to " .. tostring(hl.link)
            )
        end
    end)

    it("marks the last line of a buffer without erroring", function()
        local bufnr = scratch(LINES)
        local count = vim.api.nvim_buf_line_count(bufnr)
        assert.eq(
            render.paint(
                bufnr,
                { { id = "1", status = "attached", line_start = count, line_end = count } },
                { style = "highlight" }
            ),
            1
        )
    end)
end)
