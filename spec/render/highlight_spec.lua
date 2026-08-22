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
        vim.api.nvim_set_hl(0, highlight.GROUPS.drifted, { fg = "#ff0000" })
        highlight.setup()
        assert.is_nil(vim.api.nvim_get_hl(0, { name = highlight.GROUPS.drifted, link = true }).link)
    end)
end)

local WASH = "SidenotePenBlue"

---Read the wash's background, nil while nothing has inked the group.
---@return integer|nil
local function washed()
    return vim.api.nvim_get_hl(0, { name = WASH }).bg
end

describe("highlight.rewash", function()
    it("re-inks a wash the background changed under", function()
        local restore = vim.o.background
        vim.api.nvim_set_hl(0, WASH, {})

        vim.o.background = "dark"
        highlight.setup()
        local dark = washed()

        -- A second setup cannot move it: the group exists, and a default
        -- never overwrites one that does
        vim.o.background = "light"
        highlight.setup()
        local unmoved = washed()

        highlight.rewash()
        local light = washed()
        vim.o.background = restore

        assert.eq(unmoved, dark)
        assert.neq(light, dark)
    end)

    it("inks nothing while the wash is undefined", function()
        vim.api.nvim_set_hl(0, WASH, {})
        highlight.rewash()
        assert.is_nil(washed())
    end)
end)

---Run `fn` with `vim.g.sidenote` set to `cfg`, restoring it afterwards.
---@param cfg table<string, any> what `vim.g.sidenote` holds while fn runs
---@param fn fun()
local function configured(cfg, fn)
    local before = vim.g.sidenote
    vim.g.sidenote = cfg
    local ok, err = pcall(fn)
    vim.g.sidenote = before
    assert(ok, err)
end

describe("highlight.washes", function()
    it("is the seeded set when no pen carries shades", function()
        configured({}, function()
            assert.is_nil(highlight.washes().SidenotePenTeal)
            assert.not_nil(highlight.washes().SidenotePenBlue)
        end)
    end)

    it("carries a pen that named its own shades", function()
        configured({ pens = { teal = { dark = "#1f4f4a", light = "#ccefe9" } } }, function()
            assert.eq(highlight.washes().SidenotePenTeal.light, "#ccefe9")
        end)
    end)

    it("lets a configured pen retint a seeded group rather than collide", function()
        configured({ pens = { blue = { dark = "#000102", light = "#fdfeff" } } }, function()
            assert.eq(highlight.washes().SidenotePenBlue.dark, "#000102")
        end)
    end)
end)

describe("highlight pens carrying shades", function()
    it("inks a configured pen, and follows the background", function()
        local restore = vim.o.background
        configured({ pens = { teal = { dark = "#1f4f4a", light = "#ccefe9" } } }, function()
            vim.api.nvim_set_hl(0, "SidenotePenTeal", {})
            vim.o.background = "dark"
            highlight.setup()
            local dark = vim.api.nvim_get_hl(0, { name = "SidenotePenTeal" }).bg

            vim.o.background = "light"
            highlight.rewash()
            local light = vim.api.nvim_get_hl(0, { name = "SidenotePenTeal" }).bg

            assert.eq(dark, tonumber("1f4f4a", 16))
            assert.eq(light, tonumber("ccefe9", 16))
        end)
        vim.o.background = restore
    end)

    it("links a shade that names a highlight group instead of a color", function()
        configured({ pens = { themed = { dark = "DiffAdd", light = "DiffAdd" } } }, function()
            vim.api.nvim_set_hl(0, "SidenotePenThemed", {})
            highlight.setup()
            local hl = vim.api.nvim_get_hl(0, { name = "SidenotePenThemed", link = true })
            assert.eq(hl.link, "DiffAdd")
        end)
    end)
end)
