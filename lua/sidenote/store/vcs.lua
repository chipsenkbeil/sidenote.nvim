---Version-control provenance for a captured annotation.
---
---Provenance only: nothing in resolution reads any of this. A commit recorded
---while the file had uncommitted changes does not contain the annotated text,
---and under jj the working-copy commit is rewritten constantly, so a recorded
---id is a rough "when", never a content reference.
---@class sidenote.store.vcs
local M = {}

---Run git in `dir` and return its trimmed output.
---@param dir string directory git runs in
---@param args string[] arguments after the directory
---@return string|nil output nil when git exits non-zero
local function git(dir, args)
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

---Find the nearest directory at or above `path` containing `marker`.
---@param path string a file or a directory
---@param marker string name looked for in each candidate directory
---@return string|nil nil when no ancestor holds the marker
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

---Read the working copy's change id.
---
---A change id survives the rewrites that constantly replace the working-copy
---commit, so it is the stable name for the change an annotation belongs to.
---@param root string directory holding .jj
---@return string|nil change nil when jj is absent or `root` is no real repository
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

---Record the provenance of the file at `path`.
---@param path string absolute path to the annotated file
---@return sidenote.Vcs|nil vcs nil outside a repository git can read
function M.probe(path)
    local git_root = find_up(path, ".git")
    if not git_root then
        -- A non-colocated jj repository has no .git, so there is no commit id
        -- to record, and reporting nothing beats reporting a guess
        return nil
    end

    local commit = git(git_root, { "rev-parse", "HEAD" })
    if not commit then
        return nil
    end

    local jj_root = find_up(path, ".jj")
    local status = git(git_root, { "status", "--porcelain", "--", path })
    return {
        kind = jj_root and "jj" or "git",
        commit = commit,
        change = jj_root and jj_change(jj_root) or nil,
        dirty = status ~= nil and status ~= "",
    }
end

return M
