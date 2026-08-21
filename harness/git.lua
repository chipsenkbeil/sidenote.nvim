---Git plumbing for the anchoring regression harness.
---@class harness.git
local M = {}

---@class harness.git.Opts
---@field base_rev string revision the requested lines are numbered against
---@field path string file to blame, relative to the repo
---@field ranges {[1]: integer, [2]: integer}[] first/last line pairs to ask about

---Run git in `repo` with `args`.
---@param repo string
---@param args string[]
---@return string|nil stdout nil when git exits non-zero
function M.run(repo, args)
    local cmd = { "git", "-C", repo }
    vim.list_extend(cmd, args)
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
        return nil
    end
    return out
end

---Read `path` as it stood at `rev`.
---@param repo string
---@param rev string
---@param path string
---@return string|nil content nil when the path did not exist at that revision
function M.show(repo, rev, path)
    return M.run(repo, { "show", ("%s:%s"):format(rev, path) })
end

---Read the commit id at `repo`'s HEAD.
---@param repo string
---@return string head full commit id, empty when git cannot read HEAD
function M.head(repo)
    local out = M.run(repo, { "rev-parse", "HEAD" })
    return ((out or ""):gsub("%s+$", ""))
end

---Map each line of `opts.ranges` to the line it became at HEAD.
---@param repo string
---@param opts harness.git.Opts
---@return table<integer, integer> mapping of old line -> new line, absent when it died
function M.alive(repo, opts)
    local head = M.head(repo)
    local args = { "blame", "--reverse", "--porcelain", ("%s..HEAD"):format(opts.base_rev) }
    for _, range in ipairs(opts.ranges) do
        args[#args + 1] = "-L"
        args[#args + 1] = ("%d,%d"):format(range[1], range[2])
    end
    args[#args + 1] = "--"
    args[#args + 1] = opts.path

    local out = M.run(repo, args)
    local map = {}
    if not out then
        return map
    end

    for line in (out .. "\n"):gmatch("(.-)\n") do
        -- Under `--reverse` a line is blamed to the last revision holding it,
        -- and the porcelain header reads <sha> <line-in-final> <line-in-original>
        local sha, final_line, orig_line = line:match("^(%x+)%s+(%d+)%s+(%d+)")
        if sha and sha == head then
            map[tonumber(orig_line)] = tonumber(final_line)
        end
    end
    return map
end

return M
