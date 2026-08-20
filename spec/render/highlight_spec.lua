local highlight = require("sidenote.highlight")

local STATUSES = { "attached", "drifted", "ambiguous", "orphaned", "filegone" }

describe("highlight.GROUPS", function()
    it("names a group for every status", function()
        for _, status in ipairs(STATUSES) do
            assert.is_type(highlight.GROUPS[status], "string")
        end
    end)

    it("gives every status a distinct group, so confidence is visible", function()
        local seen = {}
        for _, status in ipairs(STATUSES) do
            local group = highlight.GROUPS[status]
            assert.is_nil(seen[group], "duplicate group for " .. status)
            seen[group] = true
        end
    end)

    it("prefixes every group so it cannot collide with another plugin", function()
        for _, status in ipairs(STATUSES) do
            assert.match(highlight.GROUPS[status], "^Sidenote")
        end
    end)
end)

describe("highlight.SIGNS", function()
    it("gives every status a sign", function()
        for _, status in ipairs(STATUSES) do
            assert.is_type(highlight.SIGNS[status], "string")
        end
    end)

    it("keeps every sign within two display cells", function()
        for _, status in ipairs(STATUSES) do
            assert.lte(vim.fn.strdisplaywidth(highlight.SIGNS[status]), 2)
        end
        assert.lte(vim.fn.strdisplaywidth(highlight.TODO.open), 2)
        assert.lte(vim.fn.strdisplaywidth(highlight.TODO.done), 2)
    end)

    it("gives every status its own glyph", function()
        -- The browser lists annotations away from their source, so the sign is
        -- the only thing carrying status; sharing one would erase the difference
        local seen = {}
        for _, status in ipairs(STATUSES) do
            local sign = highlight.SIGNS[status]
            assert.is_nil(seen[sign], ("%s and %s share %q"):format(status, seen[sign] or "", sign))
            seen[sign] = status
        end
    end)
end)

describe("highlight.MARKS", function()
    it("names a marker group for every status, apart from the sign groups", function()
        for _, status in ipairs(STATUSES) do
            assert.is_type(highlight.MARKS[status], "string")
            assert.neq(highlight.MARKS[status], highlight.GROUPS[status])
        end
    end)

    it("marks a healthy note like a highlighter pen, with a background", function()
        -- Ink over words: the sign groups color a glyph, so reusing them here
        -- tinted the text instead of marking it
        highlight.setup()
        local hl = vim.api.nvim_get_hl(0, { name = highlight.MARKS.attached, link = true })
        assert.not_nil(hl.link)
    end)
end)

describe("highlight pens", function()
    local PENS = { "SidenotePenYellow", "SidenotePenCoral", "SidenotePenBlue", "SidenotePenGreen" }

    it("gives each seeded pen a background wash, the way a highlighter reads", function()
        highlight.setup()
        for _, group in ipairs(PENS) do
            local hl = vim.api.nvim_get_hl(0, { name = group })
            assert.not_nil(hl.bg, group .. " has no background")
            assert.is_nil(hl.fg, group .. " sets a foreground over the code's own")
        end
    end)

    it("defers to a colorscheme that already colored a pen", function()
        vim.api.nvim_set_hl(0, "SidenotePenCoral", { bg = "#123456" })
        highlight.setup()
        assert.eq(vim.api.nvim_get_hl(0, { name = "SidenotePenCoral" }).bg, 0x123456)
    end)
end)

describe("highlight.setup", function()
    it("defines every group", function()
        highlight.setup()
        for _, status in ipairs(STATUSES) do
            assert.not_nil(vim.api.nvim_get_hl(0, { name = highlight.GROUPS[status] }))
        end
    end)

    it("links to standard groups so a colorscheme decides the colors", function()
        highlight.setup()
        local hl = vim.api.nvim_get_hl(0, { name = highlight.GROUPS.attached, link = true })
        assert.not_nil(hl.link)
    end)

    it("is idempotent", function()
        highlight.setup()
        highlight.setup()
        assert.not_nil(vim.api.nvim_get_hl(0, { name = highlight.GROUPS.orphaned }))
    end)

    it("defers to a colorscheme that already defined a group", function()
        -- `default = true` means our link never overrides a user's choice
        vim.api.nvim_set_hl(0, highlight.GROUPS.drifted, { fg = "#ff0000" })
        highlight.setup()
        assert.is_nil(vim.api.nvim_get_hl(0, { name = highlight.GROUPS.drifted, link = true }).link)
    end)
end)
