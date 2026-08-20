local confirm = require("sidenote.browser.confirm")

local ID = "01J9F3K2X7Q4V8M2ZC5T0BQWE"
local OTHER = "01J9F3K2X7Q4V8M2ZC5T0BQWF"

---@param actions sidenote.browser.Action[]
---@return string
local function text(actions)
    return table.concat(confirm.summary(actions), "\n")
end

---Line number the lossy rule sits on, or nil when there is none.
---@param actions sidenote.browser.Action[]
---@return integer|nil
local function rule_at(actions)
    for i, line in ipairs(confirm.summary(actions)) do
        if line:find(confirm.RULE, 1, true) then
            return i
        end
    end
    return nil
end

---@param actions sidenote.browser.Action[]
---@param needle string
---@return integer|nil
local function line_at(actions, needle)
    for i, line in ipairs(confirm.summary(actions)) do
        if line:find(needle, 1, true) then
            return i
        end
    end
    return nil
end

local WRITE = { kind = "write", id = ID, lossy = false, prose = { "new" } }
local CHANGE =
    { kind = "change", id = ID, lossy = false, field = "kind", from = "note", to = "todo" }
local MOVE = {
    kind = "move",
    id = ID,
    lossy = false,
    from = "lua/lobby.lua:88",
    to = "lua/net/lobby.lua:31",
}
local RESCOPE = {
    kind = "rescope",
    id = ID,
    lossy = true,
    from = "lua/lobby.lua:42-57",
    to = "lua/lobby.lua",
}
local DELETE = { kind = "delete", id = ID, lossy = true }

describe("browser.confirm.summary", function()
    it("names every action kind it was given", function()
        local body = text({ WRITE, CHANGE, MOVE, RESCOPE, DELETE })
        for _, word in ipairs({ "WRITE", "CHANGE", "MOVE", "RESCOPE", "DELETE" }) do
            assert.contains(body, word)
        end
    end)

    it("counts the total in its opening line", function()
        assert.contains(confirm.summary({ WRITE, CHANGE, DELETE })[1], "3")
    end)

    it("aggregates actions of one kind into a single counted line", function()
        local other = vim.tbl_extend("force", WRITE, { id = OTHER })
        assert.contains(text({ WRITE, other }), "2")
        assert.eq(#confirm.summary({ WRITE, other }), #confirm.summary({ WRITE }))
    end)

    it("reads naturally for a single annotation", function()
        assert.contains(text({ DELETE }), "1 annotation")
        assert.falsy(text({ DELETE }):find("1 annotations", 1, true))
    end)
end)

describe("browser.confirm lossy grouping", function()
    it("puts lossy actions below the rule and the rest above it", function()
        local actions = { WRITE, CHANGE, MOVE, RESCOPE, DELETE }
        local rule = assert.not_nil(rule_at(actions))
        assert.lt(assert.not_nil(line_at(actions, "WRITE")), rule)
        assert.lt(assert.not_nil(line_at(actions, "MOVE")), rule)
        assert.gt(assert.not_nil(line_at(actions, "RESCOPE")), rule)
        assert.gt(assert.not_nil(line_at(actions, "DELETE")), rule)
    end)

    it("draws no rule when nothing loses information", function()
        assert.is_nil(rule_at({ WRITE, CHANGE, MOVE }))
    end)

    it("keeps a non-lossy rescope above the rule", function()
        -- Grouping is by what an action costs, not by which kind it is
        local narrowing =
            vim.tbl_extend("force", RESCOPE, { lossy = false, to = "lua/lobby.lua:45" })
        local actions = { narrowing, DELETE }
        assert.lt(assert.not_nil(line_at(actions, "RESCOPE")), assert.not_nil(rule_at(actions)))
    end)
end)

describe("browser.confirm callouts", function()
    it("shows both locations for a move, and says the anchor is re-taken", function()
        local body = text({ MOVE })
        assert.contains(body, "lua/lobby.lua:88")
        assert.contains(body, "lua/net/lobby.lua:31")
        assert.contains(body, "re-anchored by content")
    end)

    it("warns that widening to file scope drops the anchor", function()
        assert.contains(text({ RESCOPE }), "DROPS ANCHOR")
    end)

    it("says a non-lossy rescope is re-anchored, never that it drops the anchor", function()
        -- The note follows what the action costs, not which kind it is
        local narrowing =
            vim.tbl_extend("force", RESCOPE, { lossy = false, to = "lua/lobby.lua:45" })
        local body = text({ narrowing })
        assert.contains(body, "re-anchored by content")
        assert.falsy(body:find("DROPS ANCHOR", 1, true))
    end)

    it("says a move that widens to file scope drops the anchor", function()
        local widening = vim.tbl_extend("force", MOVE, { lossy = true, to = "lua/net/lobby.lua" })
        local body = text({ widening })
        assert.contains(body, "DROPS ANCHOR")
        assert.falsy(body:find("re-anchored", 1, true))
    end)

    it("warns that a delete removes the prose file", function()
        -- The one action that destroys a document rather than a record
        assert.contains(text({ DELETE }), "REMOVES PROSE FILE")
    end)

    it("shows what a change is changing", function()
        assert.contains(text({ CHANGE }), "note -> todo")
    end)

    it("shows a pen picked up or put down as the placeholder", function()
        -- A nil side is rendered, not formatted: %s on nil would throw
        local picked =
            { kind = "change", id = ID, lossy = false, field = "pen", from = nil, to = "yellow" }
        assert.contains(text({ picked }), "- -> yellow")
        local dropped =
            { kind = "change", id = ID, lossy = false, field = "pen", from = "yellow", to = nil }
        assert.contains(text({ dropped }), "yellow -> -")
    end)

    it("returns nothing at all when there are no actions", function()
        assert.eq_deep(confirm.summary({}), {})
    end)
end)
