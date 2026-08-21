local location = require("sidenote.location")

---@class sidenote.browser.Action
---@field kind "write"|"change"|"rescope"|"move"|"delete" what to do
---@field id string annotation acted on
---@field lossy boolean whether applying it discards something unrecoverable
---@field lnum integer|nil buffer line the edit was read from, so an error can name it
---@field field string|nil column that changed, for a change
---@field from string|nil value being replaced, for change, rescope and move
---@field to string|nil value replacing it, for change, rescope and move
---@field prose string[]|nil the note's new prose, for a write
---@field summary string|nil first prose line, for a delete to quote

---Turns an edited buffer into the actions that would make it true.
---
---Compares against what was rendered rather than against the store, so an
---untouched row can never produce an action. Pure, and blind to whether any of
---the actions are possible: that is the consumer's job.
---@class sidenote.browser.diff
local M = {}

---Columns whose edit means the same thing whatever the value.
---
---Pen included: the `-` placeholder parses to nil, exactly as a record with no
---pen holds nil, so the placeholder never diffs.
local COLUMNS = { "kind", "state", "pen" }

---@param a string[]
---@param b string[]
---@return boolean
local function same_lines(a, b)
    if #a ~= #b then
        return false
    end
    for i, line in ipairs(a) do
        if line ~= b[i] then
            return false
        end
    end
    return true
end

---Turn an edited location column into the action that re-points the note.
---
---A move when the path changed, a rescope otherwise. Only widening to file
---scope is lossy: every other edit re-anchors from the file as it is now, so
---nothing that could be recovered is discarded.
---@param row sidenote.browser.Row
---@param parsed sidenote.browser.Parsed
---@return sidenote.browser.Action|nil action nil when the location is unchanged
local function relocation(row, parsed)
    local rec = row.entry.record
    local from = location.format(rec)
    if from == parsed.location then
        return nil
    end

    local wanted = location.parse(parsed.location)
    local moved = wanted ~= nil and wanted.path ~= rec.path
    return {
        kind = moved and "move" or "rescope",
        id = rec.id,
        lnum = parsed.lnum,
        from = from,
        to = parsed.location,
        lossy = wanted ~= nil and wanted.scope == "file" and rec.scope ~= "file",
    }
end

---@param before sidenote.browser.State what the browser rendered
---@param after sidenote.browser.Parsed[] what the user left behind
---@return sidenote.browser.Action[]
function M.compute(before, after)
    local rendered = {}
    for _, row in ipairs(before.rows) do
        rendered[row.entry.id] = row
    end

    local actions, kept = {}, {}
    for _, parsed in ipairs(after) do
        local row = rendered[parsed.id]
        -- A row naming an id the baseline never rendered is the caller's to
        -- refuse; diffing it against nothing would invent an edit
        if row then
            kept[parsed.id] = true
            for _, column in ipairs(COLUMNS) do
                local was = row.entry.record[column]
                if was ~= parsed[column] then
                    actions[#actions + 1] = {
                        kind = "change",
                        id = parsed.id,
                        lnum = parsed.lnum,
                        lossy = false,
                        field = column,
                        from = was,
                        to = parsed[column],
                    }
                end
            end

            local relocated = relocation(row, parsed)
            if relocated then
                actions[#actions + 1] = relocated
            end

            if not same_lines(row.prose, parsed.prose) then
                actions[#actions + 1] = {
                    kind = "write",
                    id = parsed.id,
                    lnum = parsed.lnum,
                    lossy = false,
                    prose = parsed.prose,
                }
            end
        end
    end

    for _, row in ipairs(before.rows) do
        local id = row.entry.id
        if not kept[id] then
            -- Lossy: unlike every other action this destroys a document the
            -- user wrote, not a record the store can rebuild
            actions[#actions + 1] =
                { kind = "delete", id = id, lossy = true, summary = row.prose[1] }
        end
    end
    return actions
end

---Find deleted notes whose prose was left behind, glued onto the note above.
---
---A header deleted on its own leaves its prose in place, and the grammar hands
---every unmarked line to the previous note, so the diff reads it as a rewrite
---of a neighbor nobody touched, beside the delete.
---@param before sidenote.browser.State what the browser rendered
---@param actions sidenote.browser.Action[] what `compute` derived
---@return sidenote.browser.ParseError[] errors one per note left behind
function M.orphans(before, actions)
    local writes, deleted = {}, {}
    for _, action in ipairs(actions) do
        if action.kind == "write" then
            writes[action.id] = action
        elseif action.kind == "delete" then
            deleted[action.id] = true
        end
    end

    local errors = {}
    for i, row in ipairs(before.rows) do
        local write = writes[row.entry.id]
        if write then
            local expected = vim.list_slice(row.prose)
            for n = i + 1, #before.rows do
                local dead = before.rows[n]
                if not deleted[dead.entry.id] then
                    break
                end
                vim.list_extend(expected, dead.prose)
                if same_lines(write.prose, expected) then
                    errors[#errors + 1] = {
                        lnum = write.lnum or 0,
                        message = ("%s was deleted but its prose remains here; delete those lines too"):format(
                            dead.entry.id
                        ),
                    }
                    break
                end
            end
        end
    end
    return errors
end

return M
