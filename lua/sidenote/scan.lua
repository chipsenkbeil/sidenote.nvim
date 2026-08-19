local project = require("sidenote.store.project")
local resolve = require("sidenote.core.resolve")
local store = require("sidenote.store")
local strategy = require("sidenote.store.strategy")

---@class sidenote.scan.Opts
---@field path string a file inside the project, or the project root itself
---@field config sidenote.Config resolved configuration

---Resolves every annotation in a project against the files it points into.
---
---The counterpart to `session`, which resolves one buffer. Nothing here needs
---a buffer to exist, so it works in a headless run — but where one is loaded
---its text wins, so an interactive caller sees unsaved edits.
---@class sidenote.scan
local M = {}

---@param path string absolute path of a source file
---@return string|nil content nil when the file no longer exists
local function content_of(path)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name ~= "" and (vim.uv.fs_realpath(name) or name) == path then
                return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
            end
        end
    end
    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end
    return table.concat(vim.fn.readfile(path, "b"), "\n")
end

---Every record in the project's stores, with the root it came from.
---
---Earlier roots win on an id conflict, matching the read precedence a strategy
---list already has.
---@param roots string[]
---@return {root: string, record: sidenote.Annotation}[]
local function records(roots)
    local found, seen = {}, {}
    for _, root in ipairs(roots) do
        for _, id in ipairs(store.ids(root)) do
            if not seen[id] then
                local rec = store.read(root, id)
                if rec and rec.path then
                    seen[id] = true
                    found[#found + 1] = { root = root, record = rec }
                end
            end
        end
    end
    return found
end

---Resolve every annotation the project holds.
---
---Sorted by path and then by line, so two runs over unchanged input produce
---the same order and a diff between them means something.
---@param opts sidenote.scan.Opts
---@return sidenote.session.Entry[]
function M.project(opts)
    local roots = strategy.resolve(opts.path, opts.config)
    if not roots then
        return {}
    end

    local root = project.root(opts.path)
    local cache = {}
    local entries = {}
    for _, held in ipairs(records(roots)) do
        local rec = held.record
        -- Each source file is read once however many notes target it
        if cache[rec.path] == nil then
            local absolute = root and (root .. "/" .. rec.path) or rec.path
            cache[rec.path] = { content = content_of(absolute) }
        end

        local resolution = resolve.resolve(rec, cache[rec.path].content)
        entries[#entries + 1] = {
            id = rec.id,
            status = resolution.status,
            line_start = resolution.line_start,
            line_end = resolution.line_end,
            root = held.root,
            record = rec,
            resolution = resolution,
        }
    end

    table.sort(entries, function(a, b)
        if a.record.path ~= b.record.path then
            return a.record.path < b.record.path
        end
        return (a.line_start or math.huge) < (b.line_start or math.huge)
    end)
    return entries
end

return M
