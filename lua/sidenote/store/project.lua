---Project root detection and stable project identity.
---@class sidenote.store.project
local M = {}

---Root markers in priority order.
---
---`.sidenote` leads so that creating that directory is enough to declare a
---project, with no VCS and no configuration. `*.rockspec` is a glob rather than
---a name, since its version is part of the filename.
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
---@param marker string a filename, or a glob when it holds a `*`
---@return boolean
local function present(dir, marker)
    if not marker:find("*", 1, true) then
        return vim.uv.fs_stat(dir .. "/" .. marker) ~= nil
    end
    return #vim.fn.glob(dir .. "/" .. marker, true, true) > 0
end

---@param dir string
---@return boolean
local function is_root(dir)
    for _, marker in ipairs(M.MARKERS) do
        if present(dir, marker) then
            return true
        end
    end
    return false
end

---Nearest project root at or above `path`, or nil when nothing marks one.
---@param path string a file or a directory
---@return string|nil
function M.root(path)
    local start = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
    if is_root(start) then
        return start
    end
    for dir in vim.fs.parents(start) do
        if is_root(dir) then
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
