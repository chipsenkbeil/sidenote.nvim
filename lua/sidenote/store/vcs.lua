---Version-control provenance for a captured annotation.
---
---Provenance only: nothing in resolution reads any of this. A commit recorded
---while the file had uncommitted changes does not contain the annotated text,
---and under jj the working-copy commit is rewritten constantly, so a recorded
---id is a rough "when", never a content reference.
---@class sidenote.store.vcs
local M = {}

---@param dir string
---@param args string[]
---@return string|nil
local function run(dir, args)
    local cmd = { "git", "-C", dir }
    for _, arg in ipairs(args) do
        cmd[#cmd + 1] = arg
    end
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
        return nil
    end
    return (out:gsub("%s+$", ""))
end

---Nearest directory at or above `path` containing `marker`.
---@param path string
---@param marker string
---@return string|nil
local function find_up(path, marker)
    local start = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
    if vim.uv.fs_stat(start .. "/" .. marker) then
        return start
    end
    for dir in vim.fs.parents(start) do
        if vim.uv.fs_stat(dir .. "/" .. marker) then
            return dir
        end
    end
    return nil
end

---The working copy's change id, the stable name a review filter keys on.
---
---A jj change id survives the rewrites that constantly replace the
---working-copy commit, which is what makes it usable as "the change these
---review comments belong to". Nil when jj is absent or the directory is no
---real repository.
---@param root string directory holding .jj
---@return string|nil
local function jj_change(root)
    if vim.fn.executable("jj") == 0 then
        return nil
    end
    local out = vim.fn.system({
        "jj",
        "-R",
        root,
        "--no-pager",
        "log",
        "--no-graph",
        "-r",
        "@",
        "-T",
        "change_id",
    })
    if vim.v.shell_error ~= 0 then
        return nil
    end
    return (out:gsub("%s+$", ""))
end

---@param path string
---@return sidenote.Vcs|nil
function M.probe(path)
    local git_root = find_up(path, ".git")
    if not git_root then
        -- A non-colocated jj repository has no .git to read, so there is no
        -- commit id to record. Reporting nothing beats reporting a guess
        return nil
    end

    local commit = run(git_root, { "rev-parse", "HEAD" })
    if not commit then
        return nil
    end

    local jj_root = find_up(path, ".jj")
    local status = run(git_root, { "status", "--porcelain", "--", path })
    return {
        kind = jj_root and "jj" or "git",
        commit = commit,
        change = jj_root and jj_change(jj_root) or nil,
        dirty = status ~= nil and status ~= "",
    }
end

return M
