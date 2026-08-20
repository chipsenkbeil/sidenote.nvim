local buffer = require("sidenote.buffer")
local location = require("sidenote.location")
local project = require("sidenote.store.project")
local record = require("sidenote.core.record")
local store = require("sidenote.store")

---Executes confirmed browser edits against the store.
---
---The only module in the browser that writes anything, which is what keeps
---rendering, parsing and diffing testable without a store at all.
---@class sidenote.browser.apply
local M = {}

---@return string
local function now()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

---Turn a location's path into something the filesystem understands.
---
---Locations are written project-relative for display, but the grammar accepts
---an absolute path too.
---@param state sidenote.browser.State
---@param path string
---@return string
local function absolute(state, path)
    if path:sub(1, 1) == "/" then
        return path
    end
    local root = project.root(state.path)
    return root and (root .. "/" .. path) or path
end

---@param state sidenote.browser.State
---@param path string
---@return string
local function relative(state, path)
    local root = project.root(state.path)
    return root and project.relative(root, absolute(state, path)) or path
end

---@param state sidenote.browser.State
---@param id string
---@return sidenote.browser.Row|nil
local function row_for(state, id)
    for _, row in ipairs(state.rows) do
        if row.entry.id == id then
            return row
        end
    end
    return nil
end

---@class sidenote.browser.Destination
---@field location sidenote.Location where the annotation now points, clamped
---@field content string full text of the file it points into

---Resolve a location edit against the file it now points into.
---@param action sidenote.browser.Action
---@param state sidenote.browser.State
---@return sidenote.browser.Destination|nil
---@return string|nil err
local function destination(action, state)
    local wanted, parse_err = location.parse(action.to)
    if not wanted then
        return nil, parse_err
    end
    local content = buffer.read(absolute(state, wanted.path))
    local checked, err = location.validate(wanted, content)
    if not checked then
        return nil, err
    end
    return { location = checked, content = content }, nil
end

---@param path string
---@return boolean
local function open_and_modified(path)
    local wanted = vim.uv.fs_realpath(path) or path
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].modified then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if (vim.uv.fs_realpath(name) or name) == wanted then
                return true
            end
        end
    end
    return false
end

---Checks that need the filesystem, which is why they live here rather than in
---the parser.
---@type table<string, fun(action: sidenote.browser.Action, state: sidenote.browser.State): string|nil>
local CHECKS = {}

CHECKS.move = function(action, state)
    local _, err = destination(action, state)
    return err
end

CHECKS.rescope = CHECKS.move

CHECKS.change = function(action, state)
    -- The parser checks only a pen's shape; whether it is configured is
    -- answered here, where the config is
    if action.field == "pen" and action.to ~= nil then
        local pens = state.config.pens or {}
        if not pens[action.to] then
            local known = vim.tbl_keys(pens)
            table.sort(known)
            return ("unknown pen %q; configured pens: %s"):format(
                action.to,
                table.concat(known, ", ")
            )
        end
    end
    return nil
end

CHECKS.write = function(action, state)
    local row = row_for(state, action.id)
    if not row then
        return ("no annotation %s in this browser"):format(tostring(action.id))
    end
    local path = store.prose_target(row.entry.root, action.id, state.config.filetype)
    if open_and_modified(path) then
        return ("%s is open with unsaved changes; save or discard it first"):format(path)
    end
    return nil
end

---@type table<string, fun(action: sidenote.browser.Action, state: sidenote.browser.State): boolean, string|nil>
local APPLIERS = {}

APPLIERS.delete = function(action, state)
    local row = row_for(state, action.id)
    if not row then
        return false, ("no annotation %s to delete"):format(tostring(action.id))
    end
    if not store.delete(row.entry.root, action.id, state.config.filetype) then
        return false, ("%s was already gone"):format(action.id)
    end
    return true, nil
end

APPLIERS.write = function(action, state)
    local row = row_for(state, action.id)
    if not row then
        return false, ("no annotation %s to write"):format(tostring(action.id))
    end
    return store.write_prose({
        root = row.entry.root,
        id = action.id,
        filetype = state.config.filetype,
        lines = action.prose,
    })
end

APPLIERS.change = function(action, state)
    local row = row_for(state, action.id)
    if not row then
        return false, ("no annotation %s to change"):format(tostring(action.id))
    end
    -- Re-read rather than reuse the rendered snapshot, so two edits to one row
    -- in the same pass do not undo each other
    local rec, err = store.read(row.entry.root, action.id)
    if not rec then
        return false, err or ("could not read %s"):format(action.id)
    end
    rec[action.field] = action.to
    return store.update(row.entry.root, rec)
end

---@param action sidenote.browser.Action
---@param state sidenote.browser.State
---@return boolean ok
---@return string|nil err
local function reanchor(action, state)
    local row = row_for(state, action.id)
    if not row then
        return false, ("no annotation %s to relocate"):format(tostring(action.id))
    end
    local dest, dest_err = destination(action, state)
    if not dest then
        return false, dest_err
    end
    local rec, err = store.read(row.entry.root, action.id)
    if not rec then
        return false, err or ("could not read %s"):format(action.id)
    end

    local wanted = dest.location
    return store.update(
        row.entry.root,
        record.reanchor(rec, {
            path = relative(state, wanted.path),
            content = dest.content,
            scope = wanted.scope,
            line_start = wanted.line_start,
            line_end = wanted.line_end,
            col_start = wanted.col_start,
            col_end = wanted.col_end,
            now = now(),
        })
    )
end

APPLIERS.move = reanchor
APPLIERS.rescope = reanchor

---Everything that would stop an action being possible, gathered before any of
---them run.
---
---Validation is separate from applying so that no confirmation dialog ever
---offers something impossible.
---@param actions sidenote.browser.Action[]
---@param state sidenote.browser.State
---@return sidenote.browser.ParseError[]
function M.validate(actions, state)
    local errors = {}
    for _, action in ipairs(actions) do
        local check = CHECKS[action.kind]
        local err = check and check(action, state)
        if err then
            errors[#errors + 1] = { lnum = action.lnum or 0, message = err }
        end
    end
    return errors
end

---Apply confirmed actions, reporting how many landed and what did not.
---
---One failure never abandons the rest: a browser write is a batch, and losing
---four good edits to one bad one would be worse than the bad one.
---@param actions sidenote.browser.Action[]
---@param state sidenote.browser.State
---@return integer applied
---@return string[] failures
function M.run(actions, state)
    local applied, failures = 0, {}
    for _, action in ipairs(actions) do
        local applier = APPLIERS[action.kind]
        if not applier then
            failures[#failures + 1] = ("unknown action %q"):format(tostring(action.kind))
        else
            local ok, err = applier(action, state)
            if ok then
                applied = applied + 1
            else
                failures[#failures + 1] = err or ("%s failed"):format(action.kind)
            end
        end
    end
    return applied, failures
end

return M
