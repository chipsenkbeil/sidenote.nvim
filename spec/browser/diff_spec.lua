local diff = require("sidenote.browser.diff")

local ID = "01J9F3K2X7Q4V8M2ZC5T0BQWE"
local OTHER = "01J9F3K2X7Q4V8M2ZC5T0BQWF"

---@class spec.browser.RowSpec
---@field id? string annotation id, defaults to the stub ULID
---@field create? boolean true for a row the user typed, which carries no id
---@field kind? "note"|"todo" defaults to note
---@field state? string lifecycle position, defaults to open
---@field pen? string pen name, defaults to none
---@field path? string defaults to lua/lobby.lua
---@field line_start? integer defaults to 42
---@field line_end? integer defaults to line_start
---@field scope? "file"|"lines" defaults to lines
---@field prose? string[] defaults to one summary line

---@param spec spec.browser.RowSpec
---@return string
local function location_of(spec)
    local path = spec.path or "lua/lobby.lua"
    if spec.scope == "file" then
        return path
    end
    local line_start = spec.line_start or 42
    local line_end = spec.line_end or line_start
    if line_start == line_end then
        return ("%s:%d"):format(path, line_start)
    end
    return ("%s:%d-%d"):format(path, line_start, line_end)
end

---What the browser rendered, which is the baseline an edit is measured from.
---@param specs spec.browser.RowSpec[]
---@return sidenote.browser.State
local function before(specs)
    local rows = {}
    for i, spec in ipairs(specs) do
        local line_start = spec.line_start or 42
        local whole_file = spec.scope == "file"
        rows[i] = {
            entry = {
                id = spec.id or ID,
                status = "attached",
                root = "/store",
                record = {
                    id = spec.id or ID,
                    kind = spec.kind or "note",
                    state = spec.state or "open",
                    pen = spec.pen,
                    path = spec.path or "lua/lobby.lua",
                    scope = spec.scope or "lines",
                    line_start = whole_file and 0 or line_start,
                    line_end = whole_file and 0 or (spec.line_end or line_start),
                    col_start = 0,
                    col_end = 0,
                },
            },
            prose = spec.prose or { "the summary" },
        }
    end
    return { path = "/project/lua/lobby.lua", source = 0, config = {}, rows = rows }
end

---What the user left in the buffer.
---@param specs spec.browser.RowSpec[]
---@return sidenote.browser.Parsed[]
local function after(specs)
    local rows = {}
    for i, spec in ipairs(specs) do
        rows[i] = {
            id = not spec.create and (spec.id or ID) or nil,
            lnum = i,
            kind = spec.kind or "note",
            state = spec.state or "open",
            pen = spec.pen,
            location = location_of(spec),
            prose = spec.prose or { "the summary" },
            fields = {},
        }
    end
    return rows
end

---@param actions sidenote.browser.Action[]
---@param kind string
---@return sidenote.browser.Action|nil
local function find(actions, kind)
    for _, action in ipairs(actions) do
        if action.kind == kind then
            return action
        end
    end
    return nil
end

describe("browser.diff untouched", function()
    it("produces nothing when nothing was edited", function()
        assert.eq_deep(diff.compute(before({ {} }), after({ {} })), {})
    end)

    it("produces nothing when rows were only reordered", function()
        -- Position is not identity; the concealed id is
        local state = before({ { id = ID }, { id = OTHER } })
        local edited = after({ { id = OTHER }, { id = ID } })
        assert.eq_deep(diff.compute(state, edited), {})
    end)
end)

describe("browser.diff prose", function()
    it("reports an edited summary as a write", function()
        -- The summary is prose line one, so retitling is not its own action
        local actions = diff.compute(before({ {} }), after({ { prose = { "a new summary" } } }))
        assert.eq(#actions, 1)
        assert.eq(actions[1].kind, "write")
        assert.eq_deep(actions[1].prose, { "a new summary" })
    end)

    it("reports an edited body line as a write", function()
        local state = before({ { prose = { "summary", "body" } } })
        local actions = diff.compute(state, after({ { prose = { "summary", "edited body" } } }))
        assert.eq(#actions, 1)
        assert.eq(actions[1].kind, "write")
    end)

    it("reports emptied prose as a write, never as a delete", function()
        -- Nothing is ever auto-deleted; an empty note is a note
        local actions = diff.compute(before({ {} }), after({ { prose = {} } }))
        assert.eq(#actions, 1)
        assert.eq(actions[1].kind, "write")
        assert.eq_deep(actions[1].prose, {})
    end)

    it("does not flag a write as lossy", function()
        local actions = diff.compute(before({ {} }), after({ { prose = { "new" } } }))
        assert.falsy(actions[1].lossy)
    end)
end)

describe("browser.diff change", function()
    it("reports an edited kind", function()
        local actions = diff.compute(before({ {} }), after({ { kind = "todo" } }))
        assert.eq(#actions, 1)
        assert.eq(actions[1].kind, "change")
        assert.eq(actions[1].field, "kind")
        assert.eq(actions[1].from, "note")
        assert.eq(actions[1].to, "todo")
    end)

    it("reports an edited state", function()
        local actions = diff.compute(before({ {} }), after({ { state = "wontfix" } }))
        assert.eq(#actions, 1)
        assert.eq(actions[1].field, "state")
        assert.eq(actions[1].to, "wontfix")
    end)

    it("reports a pen picked up where there was none", function()
        local actions = diff.compute(before({ {} }), after({ { pen = "yellow" } }))
        assert.eq(#actions, 1)
        assert.eq(actions[1].field, "pen")
        assert.is_nil(actions[1].from)
        assert.eq(actions[1].to, "yellow")
    end)

    it("reports a pen put back down as a change to none", function()
        local actions = diff.compute(before({ { pen = "yellow" } }), after({ {} }))
        assert.eq(#actions, 1)
        assert.eq(actions[1].field, "pen")
        assert.eq(actions[1].from, "yellow")
        assert.is_nil(actions[1].to)
    end)

    it("produces nothing for a row whose pen column stayed the placeholder", function()
        assert.eq_deep(diff.compute(before({ {} }), after({ {} })), {})
    end)

    it("reports one action per column when both changed", function()
        local actions =
            diff.compute(before({ {} }), after({ { kind = "todo", state = "resolved" } }))
        assert.eq(#actions, 2)
    end)
end)

describe("browser.diff location", function()
    it("reports a moved position as a rescope", function()
        local actions = diff.compute(before({ {} }), after({ { line_start = 88 } }))
        assert.eq(#actions, 1)
        assert.eq(actions[1].kind, "rescope")
        assert.eq(actions[1].from, "lua/lobby.lua:42")
        assert.eq(actions[1].to, "lua/lobby.lua:88")
    end)

    it("reports a changed path as a move", function()
        local actions = diff.compute(before({ {} }), after({ { path = "lua/net/lobby.lua" } }))
        assert.eq(#actions, 1)
        assert.eq(actions[1].kind, "move")
    end)

    it("reports a changed path and position as one move, not two actions", function()
        -- The location is a single text field; which part changed decides which
        -- action it becomes
        local edited = after({ { path = "lua/net/lobby.lua", line_start = 31 } })
        local actions = diff.compute(before({ {} }), edited)
        assert.eq(#actions, 1)
        assert.eq(actions[1].kind, "move")
    end)

    it("flags a widening to file scope as lossy, because it drops the anchor", function()
        local actions = diff.compute(before({ {} }), after({ { scope = "file" } }))
        assert.eq(actions[1].kind, "rescope")
        assert.truthy(actions[1].lossy)
    end)

    it("flags a move that also widens to file scope as lossy", function()
        -- The path changed too, but the anchor is dropped all the same
        local edited = after({ { path = "lua/net.lua", scope = "file" } })
        local actions = diff.compute(before({ {} }), edited)
        assert.eq(actions[1].kind, "move")
        assert.truthy(actions[1].lossy)
    end)

    it("does not flag a narrowing rescope as lossy", function()
        local state = before({ { line_start = 42, line_end = 57 } })
        local actions = diff.compute(state, after({ { line_start = 45, line_end = 46 } }))
        assert.eq(actions[1].kind, "rescope")
        assert.falsy(actions[1].lossy)
    end)
end)

describe("browser.diff delete", function()
    it("produces no action for a row the baseline never rendered", function()
        -- A pasted foreign header is the write path's to refuse; diffing it
        -- against nothing would invent an edit
        local actions = diff.compute(before({}), after({ { id = OTHER } }))
        assert.eq_deep(actions, {})
    end)

    it("reports a vanished id as a delete", function()
        local actions = diff.compute(before({ {} }), after({}))
        assert.eq(#actions, 1)
        assert.eq(actions[1].kind, "delete")
        assert.eq(actions[1].id, ID)
    end)

    it("carries the summary on a delete, so a dialog can quote it", function()
        local state = before({ { prose = { "the summary", "a body" } } })
        local action = find(diff.compute(state, {}), "delete")
        assert.eq(assert.not_nil(action).summary, "the summary")
    end)

    it("flags a delete as lossy, because it destroys prose you wrote", function()
        local actions = diff.compute(before({ {} }), after({}))
        assert.truthy(find(actions, "delete").lossy)
    end)

    it("produces one delete for each removed row", function()
        local state = before({ { id = ID }, { id = OTHER } })
        local actions = diff.compute(state, after({}))
        assert.eq(#actions, 2)
        for _, action in ipairs(actions) do
            assert.eq(action.kind, "delete")
        end
    end)
end)

describe("browser.diff combined", function()
    it("reports every edit made to one row", function()
        local edited = after({ { kind = "todo", line_start = 88, prose = { "rewritten" } } })
        local actions = diff.compute(before({ {} }), edited)
        assert.eq(#actions, 3)
        assert.not_nil(find(actions, "change"))
        assert.not_nil(find(actions, "rescope"))
        assert.not_nil(find(actions, "write"))
    end)

    it("handles an edit and a delete in one pass", function()
        local state = before({ { id = ID }, { id = OTHER } })
        local edited = after({ { id = ID, kind = "todo" } })
        local actions = diff.compute(state, edited)
        assert.eq(#actions, 2)
        assert.not_nil(find(actions, "change"))
        assert.eq(find(actions, "delete").id, OTHER)
    end)
end)
