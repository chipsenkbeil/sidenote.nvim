---Called with everything an edit would do, to decide whether it happens.
---@alias sidenote.browser.ConfirmFn fun(actions: sidenote.browser.Action[]): boolean

---Describes pending browser edits, and asks before any of them happen.
---
---Nothing here touches the store; it only renders actions and puts the
---question. Keeping it separate is what lets the wording be tested without a
---prompt appearing.
---@class sidenote.browser.confirm
local M = {}

---Separator drawn above the actions that cost something.
M.RULE = "── these lose information ──"

---Kinds listed one line each, because the specific values are the point.
---
---Everything else is counted, since one more deletion reads the same as the
---last one.
local PER_ACTION = { move = true, rescope = true, change = true }

---Order kinds appear in, so the dialog reads the same way every time.
local ORDER = { "write", "create", "change", "move", "rescope", "delete" }

local NOTES = {
    move = "(re-anchored by content)",
    rescope = "(DROPS ANCHOR)",
    delete = "(REMOVES PROSE FILE)",
}

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
        return ("%s   %s -> %s"):format(action.field, action.from, action.to)
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
---@return string
local function row(kind, body)
    local note = NOTES[kind]
    local line = ("  %-8s %s"):format(kind:upper(), body)
    return note and (line .. "   " .. note) or line
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
                lines[#lines + 1] = row(kind, detail(action))
            end
        elseif group then
            lines[#lines + 1] = row(kind, counted(kind, #group))
        end
    end
    return lines
end

---The dialog text, with anything that costs information below a rule.
---@param actions sidenote.browser.Action[]
---@return string[]
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

---Put the question, returning whether to go ahead.
---@param actions sidenote.browser.Action[]
---@return boolean confirmed
function M.ask(actions)
    if #actions == 0 then
        return false
    end
    local prompt = table.concat(M.summary(actions), "\n")
    return vim.fn.confirm(prompt, "&Apply\n&Cancel", 2) == 1
end

return M
