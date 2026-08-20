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
    it("tracks a hidden entry without drawing it", function()
        -- A narrowed view must never cost a note its save-time truth
        local bufnr = scratch(LINES)
        local placed = render.paint(bufnr, {
            { id = "a", status = "attached", hidden = true, line_start = 2, line_end = 2 },
        }, { style = "sign" })
        assert.eq(placed, 0)
        assert.eq(#marks(bufnr), 0)
        assert.not_nil(render.extent(bufnr, "a"), "the tracker still placed")
    end)

    it("places one mark per entry", function()
        local bufnr = scratch(LINES)
        local placed = render.paint(bufnr, {
            { id = "a", status = "attached", line_start = 2, line_end = 2 },
            { id = "b", status = "orphaned", line_start = 4, line_end = 4 },
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

    it("shows a sign on every line of a multi-line annotation", function()
        -- One sign on the first line reads as a one-line note; the gutter
        -- should carry the whole extent
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 2, line_end = 4 } },
            { style = "sign" }
        )
        for row = 1, 3 do
            local covering = vim.api.nvim_buf_get_extmarks(
                bufnr,
                render.NAMESPACE,
                { row, 0 },
                { row, -1 },
                { details = true, overlap = true, type = "sign" }
            )
            assert.eq(#covering, 1, "no sign covers row " .. row)
        end
    end)

    it("puts the worst status on top when notes share a line", function()
        -- The sign column shows one glyph; an orphan hiding behind an
        -- attached note's mark would go unnoticed exactly when it matters
        local bufnr = scratch(LINES)
        render.paint(bufnr, {
            { id = "a", status = "attached", line_start = 2, line_end = 4 },
            { id = "b", status = "orphaned", line_start = 3, line_end = 3 },
        }, { style = "sign" })

        local top, top_priority
        for _, mark in ipairs(marks(bufnr)) do
            if not top_priority or mark[4].priority > top_priority then
                top, top_priority = mark[4].sign_text, mark[4].priority
            end
        end
        -- Sign text is padded to two cells on its way in
        assert.eq(vim.trim(top), highlight.SIGNS.orphaned)
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

    it("highlights the annotated text, ending where its last line does", function()
        -- The marker-pen look: the text is highlighted, never the whole-width
        -- line, so it reads as ink over words rather than a painted row
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 2, line_end = 4 } },
            { style = "highlight" }
        )
        local details = marks(bufnr)[1][4]
        assert.eq(marks(bufnr)[1][2], 1)
        assert.eq(details.end_row, 3)
        assert.eq(details.end_col, #"four")
        assert.falsy(details.hl_eol)
    end)

    it("highlights a range's exact columns", function()
        local bufnr = scratch(LINES)
        render.paint(bufnr, {
            {
                id = "a",
                status = "attached",
                line_start = 2,
                line_end = 2,
                col_start = 2,
                col_end = 3,
            },
        }, { style = "highlight" })
        local mark = marks(bufnr)[1]
        assert.eq(mark[3], 1, "starts at the range's own column")
        assert.eq(mark[4].end_col, 3)
    end)

    it("marks with the marker groups, not the sign groups", function()
        -- A sign group is a colored glyph; ink over text needs a background
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 2, line_end = 2 } },
            { style = "highlight" }
        )
        assert.eq(marks(bufnr)[1][4].hl_group, highlight.MARKS.attached)
    end)

    it("inks with a note's pen when it names one the caller knows", function()
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 2, line_end = 2, pen = "coral" } },
            { style = "highlight", pens = { coral = "SidenotePenCoral" } }
        )
        assert.eq(marks(bufnr)[1][4].hl_group, "SidenotePenCoral")
    end)

    it("falls back to the status ink for a pen the caller does not know", function()
        -- A pen dropped from the config degrades rather than erroring
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "drifted", line_start = 2, line_end = 2, pen = "gone" } },
            { style = "highlight", pens = {} }
        )
        assert.eq(marks(bufnr)[1][4].hl_group, highlight.MARKS.drifted)
    end)

    it("keeps the underline style on status, where a wash has nothing to say", function()
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 2, line_end = 2, pen = "coral" } },
            { style = "underline", pens = { coral = "SidenotePenCoral" } }
        )
        assert.eq(marks(bufnr)[1][4].hl_group, highlight.UNDERLINES.attached)
    end)

    it("inks the range overlay with the pen too", function()
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 2, line_end = 2, pen = "blue" } },
            { style = "sign", highlight = "always", pens = { blue = "SidenotePenBlue" } }
        )
        local found = false
        for _, mark in ipairs(marks(bufnr)) do
            found = found or mark[4].hl_group == "SidenotePenBlue"
        end
        assert.eq(found, true)
    end)

    it("checks a multi-line todo's box once, a tail carrying the rest", function()
        -- A checkbox on every covered line reads as that many todos; bars
        -- extend, badges mark once
        local bufnr = scratch(LINES)
        render.paint(bufnr, {
            {
                id = "a",
                status = "attached",
                kind = "todo",
                state = "open",
                summary = "do it",
                line_start = 2,
                line_end = 4,
            },
        }, { style = "sign" })

        local placed = marks(bufnr)
        assert.eq(#placed, 2)
        assert.eq(vim.trim(placed[1][4].sign_text), highlight.TODO.open)
        assert.is_nil(placed[1][4].end_row, "the box marks the first line alone")
        assert.eq(placed[2][2], 2, "the tail starts on the second covered line")
        assert.eq(placed[2][4].end_row, 3)
        assert.eq(vim.trim(placed[2][4].sign_text), highlight.TAIL)
    end)

    it("gives a hurt badge the same one-badge treatment over a span", function()
        local bufnr = scratch(LINES)
        render.paint(bufnr, {
            { id = "a", status = "orphaned", line_start = 2, line_end = 3, summary = "s" },
        }, { style = "sign" })
        local placed = marks(bufnr)
        assert.eq(#placed, 2)
        assert.eq(vim.trim(placed[1][4].sign_text), highlight.SIGNS.orphaned)
        assert.is_nil(placed[1][4].end_row)
        assert.eq(vim.trim(placed[2][4].sign_text), highlight.TAIL)
    end)

    it("signs a healthy open todo as an unchecked box", function()
        -- Kind shows only while the anchor is exact; hurt stays louder
        local bufnr = scratch(LINES)
        render.paint(bufnr, {
            {
                id = "a",
                status = "attached",
                kind = "todo",
                state = "open",
                summary = "do it",
                line_start = 2,
                line_end = 2,
            },
        }, { style = "sign" })
        assert.eq(vim.trim(marks(bufnr)[1][4].sign_text), highlight.TODO.open)
    end)

    it("checks the box off once the todo is no longer open", function()
        local bufnr = scratch(LINES)
        render.paint(bufnr, {
            {
                id = "a",
                status = "attached",
                kind = "todo",
                state = "resolved",
                summary = "did it",
                line_start = 2,
                line_end = 2,
            },
        }, { style = "sign" })
        assert.eq(vim.trim(marks(bufnr)[1][4].sign_text), highlight.TODO.done)
    end)

    it("keeps the status glyph on a hurt todo, since hurt is louder", function()
        local bufnr = scratch(LINES)
        render.paint(bufnr, {
            {
                id = "a",
                status = "drifted",
                kind = "todo",
                state = "open",
                summary = "do it",
                line_start = 2,
                line_end = 2,
            },
        }, { style = "sign" })
        assert.eq(vim.trim(marks(bufnr)[1][4].sign_text), highlight.SIGNS.drifted)
    end)

    it("dims the sign of a healthy note that has no prose yet", function()
        -- A bare anchor is a deletion candidate, and it should look like one
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 2, line_end = 2 } },
            { style = "sign" }
        )
        assert.eq(marks(bufnr)[1][4].sign_hl_group, highlight.BARE)
    end)

    it("keeps the status color on a hurt note, prose or none", function()
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "orphaned", line_start = 2, line_end = 2 } },
            { style = "sign" }
        )
        assert.eq(marks(bufnr)[1][4].sign_hl_group, highlight.GROUPS.orphaned)
    end)

    it("shows the summary at end of line when the style is summary", function()
        local bufnr = scratch(LINES)
        render.paint(bufnr, {
            { id = "a", status = "attached", line_start = 2, line_end = 2, summary = "the note" },
        }, { style = "summary" })
        local virt = marks(bufnr)[1][4].virt_text[1]
        assert.eq(virt[1], "the note")
        assert.eq(virt[2], highlight.PROSE)
    end)

    it("labels a bare anchor in the summary style, dimly", function()
        local bufnr = scratch(LINES)
        render.paint(
            bufnr,
            { { id = "a", status = "attached", line_start = 2, line_end = 2 } },
            { style = "summary" }
        )
        local virt = marks(bufnr)[1][4].virt_text[1]
        assert.contains(virt[1], "no prose")
        assert.eq(virt[2], highlight.BARE)
    end)

    it("inks the summary with the note's pen", function()
        local bufnr = scratch(LINES)
        render.paint(bufnr, {
            {
                id = "a",
                status = "attached",
                line_start = 2,
                line_end = 2,
                summary = "the note",
                pen = "coral",
            },
        }, { style = "summary", pens = { coral = "SidenotePenCoral" } })
        assert.eq(marks(bufnr)[1][4].virt_text[1][2], "SidenotePenCoral")
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

describe("render range highlights", function()
    it("overlays the range once toggled on, and takes it back off", function()
        -- The org-remark look, but opt-in per buffer the way spell is: a
        -- permanent background tint fights syntax highlighting
        local bufnr = scratch(LINES)
        local entries = { { id = "a", status = "attached", line_start = 2, line_end = 4 } }
        local opts = { style = "sign", highlight = "off" }

        render.paint(bufnr, entries, opts)
        assert.eq(#marks(bufnr), 1)

        assert.truthy(render.toggle(bufnr, opts.highlight))
        render.paint(bufnr, entries, opts)
        assert.eq(#marks(bufnr), 2)

        assert.falsy(render.toggle(bufnr, opts.highlight))
        render.paint(bufnr, entries, opts)
        assert.eq(#marks(bufnr), 1)
    end)

    it("shows highlights from the start when configured on", function()
        local bufnr = scratch(LINES)
        render.paint(bufnr, {
            { id = "a", status = "attached", line_start = 2, line_end = 4 },
        }, { style = "sign", highlight = "on" })
        assert.eq(#marks(bufnr), 2)
    end)

    it("refuses to toggle a pinned mode", function()
        local bufnr = scratch(LINES)
        assert.is_nil(render.toggle(bufnr, "always"))
        assert.is_nil(render.toggle(bufnr, "never"))
    end)

    it("adds nothing on top of the highlight style itself", function()
        local bufnr = scratch(LINES)
        render.paint(bufnr, {
            { id = "a", status = "attached", line_start = 2, line_end = 4 },
        }, { style = "highlight", highlight = "always" })
        assert.eq(#marks(bufnr), 1)
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
