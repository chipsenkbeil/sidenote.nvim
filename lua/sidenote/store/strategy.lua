local project = require("sidenote.store.project")

---Turns configuration into an ordered list of store roots.
---
---The order is both the write precedence (the first entry wins) and the read
---order (reads union every root that exists, earlier entries winning on
---conflict). Each entry is strict on its own terms, so fallback is written
---explicitly in the config rather than hidden inside a strategy's semantics.
---@class sidenote.store.strategy
local M = {}

---@class sidenote.store.strategy.Opts
---@field strategy string|string[]|fun(path: string): string|nil entries tried in order
---@field global_dir string root of the machine-wide store
---@field project_dir string directory name used for an in-project store

---@param entry string|fun(path: string): string|nil
---@param source_path string
---@param opts sidenote.store.strategy.Opts
---@return string|nil root
local function resolve_one(entry, source_path, opts)
    if type(entry) == "function" then
        return entry(source_path)
    end
    if entry == "global" then
        local root = project.root(source_path)
        local key = project.key(root or vim.fn.fnamemodify(source_path, ":h"))
        return opts.global_dir .. "/" .. key
    end
    if entry == "project" then
        local root = project.root(source_path)
        return root and (root .. "/" .. opts.project_dir) or nil
    end
    return nil
end

---@param source_path string
---@param opts sidenote.store.strategy.Opts
---@return string[]|nil roots the first is the write target
---@return string|nil err
function M.resolve(source_path, opts)
    local entries = opts.strategy
    if type(entries) == "string" or type(entries) == "function" then
        entries = { entries }
    end

    local roots = {}
    for _, entry in ipairs(entries) do
        local root = resolve_one(entry, source_path, opts)
        if root then
            roots[#roots + 1] = root
        end
    end

    if #roots == 0 then
        local names = {}
        for _, entry in ipairs(entries) do
            names[#names + 1] = type(entry) == "function" and "<function>" or tostring(entry)
        end
        return nil,
            ("no store resolved for %s; tried: %s. A 'project' strategy needs one of %s at or above the file."):format(
                source_path,
                table.concat(names, ", "),
                table.concat(project.MARKERS, ", ")
            )
    end
    return roots, nil
end

return M
