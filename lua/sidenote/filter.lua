---Which annotations pass a narrowing, shared by every surface that narrows.
---@class sidenote.filter
local M = {}

---@class sidenote.Filter
---@field status? sidenote.Status keep only annotations the resolver put here
---@field kind? "note"|"todo" keep only notes or only requests to act
---@field state? "open"|"resolved"|"wontfix"|"archived" keep only one lifecycle position
---@field path? string keep only paths containing this, literally
---@field change? string keep only notes whose jj change id starts with this
---@field commit? string keep only notes whose commit id starts with this

---Whether the entry's provenance stamp opens with `want`.
---
---A prefix, the way jj and git themselves accept one; an unstamped note
---never matches, since it belongs to no change at all.
---@param entry sidenote.session.Entry
---@param field "change"|"commit"
---@param want string
---@return boolean
local function stamped(entry, field, want)
    local vcs = entry.record.vcs
    local id = vcs and vcs[field]
    return id ~= nil and id:sub(1, #want) == want
end

---@param entry sidenote.session.Entry
---@param filter sidenote.Filter
---@return boolean
function M.survives(entry, filter)
    return (filter.status == nil or entry.status == filter.status)
        and (filter.kind == nil or entry.record.kind == filter.kind)
        and (filter.state == nil or entry.record.state == filter.state)
        and (filter.path == nil or entry.record.path:find(filter.path, 1, true) ~= nil)
        and (filter.change == nil or stamped(entry, "change", filter.change))
        and (filter.commit == nil or stamped(entry, "commit", filter.commit))
end

---The entries of `entries` that pass `filter`.
---@param entries sidenote.session.Entry[]
---@param filter sidenote.Filter|nil nil keeps everything
---@return sidenote.session.Entry[] kept `entries` itself when nothing narrows
function M.narrow(entries, filter)
    if not filter or vim.tbl_isempty(filter) then
        return entries
    end
    local kept = {}
    for _, entry in ipairs(entries) do
        if M.survives(entry, filter) then
            kept[#kept + 1] = entry
        end
    end
    return kept
end

return M
