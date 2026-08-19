-- Invoked directly as `nvim -l harness/run.lua`, nothing has set up the module
-- search path yet; under the test runner this is already done and harmless
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = ("%s/lua/?.lua;%s/lua/?/init.lua;%s/?.lua;%s"):format(root, root, root, package.path)

local git = require("harness.git")
local hash = require("sidenote.core.hash")
local record = require("sidenote.core.record")
local resolve = require("sidenote.core.resolve")

---Anchoring accuracy regression harness.
---
---Samples regions from a real file at HEAD~depth, resolves each against the
---file at HEAD, and grades the result against `git blame --reverse`. Its output
---is a checked-in baseline, so a change to the matcher is falsifiable rather
---than a matter of opinion.
---@class harness.run
local M = {}

---@class harness.Report
---@field repo string repository the samples came from
---@field path string file the samples came from, relative to the repo
---@field depth integer how many commits back the samples were taken
---@field height integer lines per sampled region
---@field samples integer number of regions measured
---@field correct integer resolved, and to the line the oracle says
---@field wrong integer resolved, but to the wrong line, or a dead block resolved
---@field false_stale integer the block survived but we declined to place it
---@field correct_stale integer the block died and we declined to place it
---@field by_tier table<string, integer> mapping of ladder tier -> times it decided

---@class harness.run.Opts
---@field repo string repository to sample
---@field path string file to sample, relative to the repo
---@field depth integer how many commits back to sample from
---@field samples integer number of regions to measure
---@field height integer lines per sampled region

---@param opts harness.run.Opts
---@return harness.Report
function M.measure(opts)
    local base_rev = ("HEAD~%d"):format(opts.depth)
    local old = assert(git.show(opts.repo, base_rev, opts.path), "cannot read file at base rev")
    local new = git.show(opts.repo, "HEAD", opts.path)
    local old_lines = hash.split(old)

    local height = opts.height
    local last = #old_lines - height + 1
    assert(last >= opts.samples, "file too short for the requested sample count")

    local step = math.max(1, math.floor(last / opts.samples))

    local starts, ranges = {}, {}
    for i = 0, opts.samples - 1 do
        local n = 1 + i * step
        starts[#starts + 1] = n
        ranges[#ranges + 1] = { n, n + height - 1 }
    end

    local truth = git.alive(opts.repo, { base_rev = base_rev, path = opts.path, ranges = ranges })

    local report = {
        repo = opts.repo,
        path = opts.path,
        depth = opts.depth,
        height = height,
        samples = #starts,
        correct = 0,
        wrong = 0,
        false_stale = 0,
        correct_stale = 0,
        by_tier = {},
    }

    for _, n in ipairs(starts) do
        local rec = record.capture({
            id = ("s%d"):format(n),
            project_key = "harness",
            path = opts.path,
            scope = "range",
            line_start = n,
            line_end = n + height - 1,
            content = old,
            now = "1970-01-01T00:00:00Z",
        })
        local res = resolve.resolve(rec, new)
        report.by_tier[res.tier] = (report.by_tier[res.tier] or 0) + 1

        local expected = truth[n]
        local placed = (res.status == "attached" or res.status == "drifted") and res.line_start
            or nil

        if placed and expected and placed == expected then
            report.correct = report.correct + 1
        elseif placed then
            report.wrong = report.wrong + 1
        elseif expected then
            report.false_stale = report.false_stale + 1
        else
            report.correct_stale = report.correct_stale + 1
        end
    end

    return report
end

---@param report harness.Report
---@param baseline harness.Report
---@return {ok: boolean, regressions: string[]}
function M.compare(report, baseline)
    local regressions = {}
    if report.wrong > baseline.wrong then
        regressions[#regressions + 1] = ("wrong placements rose from %d to %d"):format(
            baseline.wrong,
            report.wrong
        )
    end
    if report.correct < baseline.correct then
        regressions[#regressions + 1] = ("correct placements fell from %d to %d"):format(
            baseline.correct,
            report.correct
        )
    end
    return { ok = #regressions == 0, regressions = regressions }
end

-- CLI: nvim -l harness/run.lua REPO PATH DEPTH [SAMPLES] [HEIGHT]
--
-- Guarded on arg[0] so that requiring this module from the test runner, which
-- also populates _G.arg, does not kick off a measurement run
if _G.arg and _G.arg[0] and _G.arg[0]:match("run%.lua$") and _G.arg[1] then
    print(vim.json.encode(M.measure({
        repo = _G.arg[1],
        path = _G.arg[2],
        depth = tonumber(_G.arg[3]),
        samples = tonumber(_G.arg[4] or "150"),
        height = tonumber(_G.arg[5] or "8"),
    })))
end

return M
