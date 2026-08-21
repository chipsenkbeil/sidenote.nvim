---Project root detection and stable project identity.
---@class sidenote.store.project
local M = {}

---A name a root directory holds, a glob matching one, or a test of the
---directory itself.
---@alias sidenote.store.project.Marker string|fun(dir: string): boolean

---What a configuration may name the marker set with.
---
---A list is the set. A function is handed a copy of the built-ins and returns
---the set it wants, which is how a configuration adds to them.
---@alias sidenote.store.project.Markers
---| sidenote.store.project.Marker[]
---| fun(defaults: sidenote.store.project.Marker[]): sidenote.store.project.Marker[]

---@class sidenote.store.project.RootOpts
---@field markers? sidenote.store.project.Marker[] what to look for, defaulting to the configured set

---The marker a directory is a root by no matter what is configured.
---
---Self-marking is what lets `mkdir .sidenote` declare a project with no VCS
---and no configuration, so no configuration may take it away.
M.ALWAYS = ".sidenote"

---What marks a project root when nothing is configured.
---
---Any one of them is enough, so this order picks nothing between two markers:
---the nearest ancestor carrying any of them wins. What the order does decide
---is how they are named in the error a caller shows. `*.rockspec` is a glob
---rather than a name, since its version is part of the filename.
---@type sidenote.store.project.Marker[]
M.MARKERS = {
    ".sidenote",
    ".git",
    ".jj",
    ".hg",
    "Cargo.toml",
    "package.json",
    "go.mod",
    "pyproject.toml",
    "*.rockspec",
}

---@param dir string
---@param marker sidenote.store.project.Marker
---@return boolean
local function present(dir, marker)
    if type(marker) == "function" then
        return marker(dir) == true
    end
    if not marker:find("*", 1, true) then
        return vim.uv.fs_stat(dir .. "/" .. marker) ~= nil
    end
    return #vim.fn.glob(dir .. "/" .. marker, true, true) > 0
end

---Every marker in force, `M.ALWAYS` among them whatever is configured.
---
---A configured list replaces the built-ins rather than adding to them, so a
---project can be marked by exactly what you name and nothing else. To add to
---the built-ins instead of replacing them, configure a function: it is handed
---a copy of `M.MARKERS` and returns the list it wants.
---@return sidenote.store.project.Marker[]
function M.markers()
    local configured = require("sidenote.config").get().markers
    if configured == nil then
        return M.MARKERS
    end

    local wanted = configured
    if type(configured) == "function" then
        wanted = configured(vim.list_extend({}, M.MARKERS)) or {}
    end

    local out = { M.ALWAYS }
    for _, marker in ipairs(wanted) do
        if marker ~= M.ALWAYS then
            out[#out + 1] = marker
        end
    end
    return out
end

---@param dir string
---@param markers string[]
---@return boolean
local function is_root(dir, markers)
    for _, marker in ipairs(markers) do
        if present(dir, marker) then
            return true
        end
    end
    return false
end

---Nearest project root at or above `path`, or nil when nothing marks one.
---
---The nearest one wins, whatever marks it: any single marker is enough, so
---the marker list ranks nothing. A `.git` beneath your `.sidenote` is a
---nearer root than it, and takes the annotations of the files under it.
---@param path string a file or a directory
---@param opts? sidenote.store.project.RootOpts
---@return string|nil
function M.root(path, opts)
    local markers = (opts and opts.markers) or M.markers()
    local start = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
    if is_root(start, markers) then
        return start
    end
    for dir in vim.fs.parents(start) do
        if is_root(dir, markers) then
            return dir
        end
    end
    return nil
end

---Stable identity for a project.
---
---A readable basename plus a hash of the absolute path, so two projects
---sharing a name never collide.
---@param root string
---@return string
function M.key(root)
    local absolute = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")
    local name = vim.fn.fnamemodify(absolute, ":t")
    return ("%s-%s"):format(name, vim.fn.sha256(absolute):sub(1, 6))
end

---Restate `path` relative to `root`, or unchanged when it lies outside.
---@param root string
---@param path string
---@return string
function M.relative(root, path)
    return vim.fs.relpath(root, path) or path
end

return M
