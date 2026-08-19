---Git plumbing for the anchoring regression harness.
---
---Not part of the plugin runtime: this exists only to produce ground truth for
---measuring resolver accuracy, which is why it may shell out where the core
---may not.
---@class harness.git
local M = {}

---@param repo string
---@param args string[]
---@return string|nil stdout nil when git exits non-zero
function M.run(repo, args)
    local cmd = { "git", "-C", repo }
    for _, arg in ipairs(args) do
        cmd[#cmd + 1] = arg
    end
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
        return nil
    end
    return out
end

---@param repo string
---@param rev string
---@param path string
---@return string|nil
function M.show(repo, rev, path)
    return M.run(repo, { "show", ("%s:%s"):format(rev, path) })
end

---@param repo string
---@return string
function M.head(repo)
    local out = M.run(repo, { "rev-parse", "HEAD" })
    return (out or ""):gsub("%s+$", "")
end

---Which of the given old lines survive to HEAD, and where they land.
---
---`git blame --reverse` reports, for each line, the last revision in which it
---existed. A line survived iff that revision is HEAD; the porcelain header's
---first number is then its line in the final file.
---@param repo string
---@param opts {base_rev: string, path: string, ranges: integer[][]}
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
        -- Header form: <sha> <line-in-final> <line-in-original> [group-size]
        local sha, final_line, orig_line = line:match("^(%x+)%s+(%d+)%s+(%d+)")
        if sha and #sha == 40 and sha == head then
            map[tonumber(orig_line)] = tonumber(final_line)
        end
    end
    return map
end

return M
