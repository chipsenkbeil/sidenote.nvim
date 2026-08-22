local record = require("sidenote.core.record")

---Called with everything an edit would do, to decide whether it happens.
---@alias sidenote.browser.ConfirmFn fun(actions: sidenote.browser.Action[]): boolean

---Describes pending browser edits, and asks before any of them happen.
---
---Nothing here touches the store; it only renders actions and puts the
---question.
---@class sidenote.browser.confirm
local M = {}

---Separator drawn above the actions that cost something.
M.RULE = "── these lose information ──"

---Kinds listed one line each, because the specific values are the point.
---
---Deletes included: `dd` on a closed fold destroys sight-unseen, so the quoted
---summary is the moment of seeing.
local PER_ACTION = { move = true, rescope = true, change = true, delete = true }

---Most characters of a summary a delete's quote shows.
local QUOTE_MAX = 50

---Order kinds appear in, so the dialog reads the same way every time.
local ORDER = { "write", "change", "move", "rescope", "delete" }

---Say what an action does or costs, for the end of its row.
---
---By cost, not by kind: a rescope within the file keeps its anchor, and a move
---to file scope drops it.
---@param action sidenote.browser.Action
---@return string|nil callout nil when there is nothing to say
local function callout_for(action)
    if action.kind == "delete" then
        return "(REMOVES PROSE FILE)"
    end
    if action.kind == "move" or action.kind == "rescope" then
        return action.lossy and "(DROPS ANCHOR)" or "(re-anchored by content)"
    end
    return nil
end

---@param count integer
---@param singular string
---@return string
local function plural(count, singular)
    return ("%d %s%s"):format(count, singular, count == 1 and "" or "s")
end

---@param action sidenote.browser.Action
---@return string
local function detail(action)
    if action.kind == "change" then
        local from, to = action.from or record.NO_PEN, action.to or record.NO_PEN
        return ("%s   %s -> %s"):format(action.field, from, to)
    end
    if action.kind == "delete" then
        local summary = action.summary
        if not summary or summary == "" then
            return "(no prose)"
        end
        if #summary > QUOTE_MAX then
            summary = summary:sub(1, QUOTE_MAX) .. "…"
        end
        return ('"%s"'):format(summary)
    end
    return ("%s -> %s"):format(action.from, action.to)
end

---@param kind string
---@param count integer
---@return string
local function counted(kind, count)
    if kind == "write" then
        return count == 1 and "1 note's prose" or ("%d notes' prose"):format(count)
    end
    return plural(count, "annotation")
end

---@param kind string
---@param body string
---@param callout string|nil
---@return string
local function row(kind, body, callout)
    local line = ("  %-8s %s"):format(kind:upper(), body)
    return callout and (line .. "   " .. callout) or line
end

---@param actions sidenote.browser.Action[]
---@return string[]
local function describe(actions)
    local by_kind = {}
    for _, action in ipairs(actions) do
        by_kind[action.kind] = by_kind[action.kind] or {}
        table.insert(by_kind[action.kind], action)
    end

    local lines = {}
    for _, kind in ipairs(ORDER) do
        local group = by_kind[kind]
        if group and PER_ACTION[kind] then
            for _, action in ipairs(group) do
                lines[#lines + 1] = row(kind, detail(action), callout_for(action))
            end
        elseif group then
            lines[#lines + 1] = row(kind, counted(kind, #group), callout_for(group[1]))
        end
    end
    return lines
end

---Build the dialog text, with anything that costs information below a rule.
---@param actions sidenote.browser.Action[]
---@return string[] lines empty when there is nothing to apply
function M.summary(actions)
    if #actions == 0 then
        return {}
    end

    local safe, lossy = {}, {}
    for _, action in ipairs(actions) do
        table.insert(action.lossy and lossy or safe, action)
    end

    local lines = { ("sidenote: apply %s?"):format(plural(#actions, "change")), "" }
    vim.list_extend(lines, describe(safe))
    if #lossy > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "  " .. M.RULE
        vim.list_extend(lines, describe(lossy))
    end
    return lines
end

---Put the question.
---@param actions sidenote.browser.Action[]
---@return boolean confirmed false when declined, and when there is nothing to apply
function M.ask(actions)
    if #actions == 0 then
        return false
    end
    local prompt = table.concat(M.summary(actions), "\n")
    return vim.fn.confirm(prompt, "&Apply\n&Cancel", 2) == 1
end

return M
