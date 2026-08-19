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
