local hash = require("sidenote.core.hash")
local record = require("sidenote.core.record")

---Weighted fuzzy relocation scoring.
---
---Weights and thresholds follow Hypothes.is' anchoring implementation, which a
---ground-truth measurement over real git history validated for source code: at
---an accept threshold of 0.80 this trades a small number of false stales for a
---large reduction in wrong placements.
---@class sidenote.core.score
local M = {}

---@type table<string, number>
M.WEIGHTS = { quote = 50, prefix = 20, suffix = 20, pos = 2 }

local TOTAL = M.WEIGHTS.quote + M.WEIGHTS.prefix + M.WEIGHTS.suffix + M.WEIGHTS.pos

---Longest input considered by the Levenshtein pass. Bounds the O(n*m) loop.
local MAX_COMPARE = 512

---Candidate lines kept for full scoring after the cheap prefilter.
M.MAX_CANDIDATES = 60

---Minimum first-line similarity for a candidate to be scored at all.
M.PREFILTER = 0.45

---@param a string
---@param b string
---@return integer
local function levenshtein(a, b)
    local la, lb = #a, #b
    if la == 0 then
        return lb
    end
    if lb == 0 then
        return la
    end
    local prev = {}
    for j = 0, lb do
        prev[j] = j
    end
    for i = 1, la do
        local cur = { [0] = i }
        local ca = a:byte(i)
        for j = 1, lb do
            local cost = (ca == b:byte(j)) and 0 or 1
            local del, ins, sub = prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost
            local best = del
            if ins < best then
                best = ins
            end
            if sub < best then
                best = sub
            end
            cur[j] = best
        end
        prev = cur
    end
    return prev[lb]
end

---@param s string
---@return string
local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
end

---Normalized similarity in [0,1] on whitespace-trimmed text.
---@param a string
---@param b string
---@return number
function M.similarity(a, b)
    a, b = trim(a):sub(1, MAX_COMPARE), trim(b):sub(1, MAX_COMPARE)
    local la, lb = #a, #b
    local longest = math.max(la, lb)
    if longest == 0 then
        return 1
    end
    -- The ratio bounds similarity rather than estimating it; returning it would
    -- let unrelated text of a convenient length outrank a real partial match
    if math.min(la, lb) / longest < 0.5 then
        return 0
    end
    return 1 - levenshtein(a, b) / longest
end

---@class sidenote.core.score.Parts
---@field quote number similarity of the anchor text itself
---@field prefix number similarity of the lines above
---@field suffix number similarity of the lines below
---@field pos number closeness to the stored line hint

---Combine per-component similarities into a single 0..1 score.
---@param parts sidenote.core.score.Parts
---@return number
function M.candidate(parts)
    local w = M.WEIGHTS
    return (
        w.quote * parts.quote
        + w.prefix * parts.prefix
        + w.suffix * parts.suffix
        + w.pos * parts.pos
    ) / TOTAL
end

---Find the best-scoring placement for a record's anchor within `lines`.
---@param lines string[]
---@param rec sidenote.Annotation
---@return sidenote.Placement|nil
function M.best(lines, rec)
    if rec.text == "" then
        return nil
    end
    local anchor_lines = hash.split(rec.text)
    local height = #anchor_lines
    local first = anchor_lines[1]
    local total = #lines
    local last_start = total - height + 1
    if last_start < 1 then
        return nil
    end

    -- Cheap prefilter: score only lines whose first line is plausibly the
    -- anchor's, so the expensive pass runs on a bounded candidate set
    local candidates = {}
    for n = 1, last_start do
        local seed = M.similarity(lines[n], first)
        if seed >= M.PREFILTER then
            candidates[#candidates + 1] = { line = n, seed = seed }
        end
    end
    table.sort(candidates, function(x, y)
        if x.seed ~= y.seed then
            return x.seed > y.seed
        end
        return math.abs(x.line - rec.line_start) < math.abs(y.line - rec.line_start)
    end)

    local norm_anchor = hash.normalize(rec.text)
    local norm_prefix = hash.normalize(rec.prefix or "")
    local norm_suffix = hash.normalize(rec.suffix or "")
    local context = record.CONTEXT
    local best
    for i = 1, math.min(#candidates, M.MAX_CANDIDATES) do
        local n = candidates[i].line
        local quote =
            M.similarity(norm_anchor, hash.normalize(hash.slice(lines, n, n + height - 1)))
        local prefix =
            M.similarity(norm_prefix, hash.normalize(hash.slice(lines, n - context, n - 1)))
        local suffix = M.similarity(
            norm_suffix,
            hash.normalize(hash.slice(lines, n + height, n + height + context - 1))
        )
        local pos = 1 - math.abs(n - rec.line_start) / math.max(total, 1)
        if pos < 0 then
            pos = 0
        end
        local value = M.candidate({ quote = quote, prefix = prefix, suffix = suffix, pos = pos })
        if not best or value > best.score then
            best = { line_start = n, line_end = n + height - 1, score = value }
        end
    end
    return best
end

return M
