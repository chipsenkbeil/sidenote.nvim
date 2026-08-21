local hash = require("sidenote.core.hash")
local record = require("sidenote.core.record")
local score = require("sidenote.core.score")

---@alias sidenote.Status "attached"|"drifted"|"ambiguous"|"orphaned"|"filegone"

---@class sidenote.Placement
---@field line_start integer first line of the placement, 1-based
---@field line_end integer last line, inclusive
---@field score number 0..1 confidence in this placement

---@class sidenote.Resolution
---@field status sidenote.Status what the resolver concluded
---@field line_start integer|nil first resolved line, absent when nothing was placed
---@field line_end integer|nil last resolved line, inclusive
---@field col_start integer|nil first resolved byte column, when the tier knows one
---@field col_end integer|nil last resolved byte column, inclusive
---@field confidence number 0..1, and 1 for the exact tiers
---@field tier string what decided the placement, or "-" when nothing ran
---@field candidates integer[]|nil competing start lines, when status is ambiguous
---@field guess sidenote.Placement|nil best rejected placement, offered but not applied

---Deterministic anchor resolution: a record plus file bytes in, a status and a
---range out.
---
---Never mutates the record.
---@class sidenote.core.resolve
local M = {}

---Statuses the ladder can conclude with, in worsening order.
---@type string[]
M.STATUS_NAMES = { "attached", "drifted", "ambiguous", "orphaned", "filegone" }

---@type table<string, boolean>
M.STATUSES = {}
for _, name in ipairs(M.STATUS_NAMES) do
    M.STATUSES[name] = true
end

---Score at or above which a fuzzy match is placed.
---
---Measured, not chosen: a lower bar buys back few anchors and costs many wrong
---placements, and a wrong placement points at code the note never meant.
M.ACCEPT = 0.80

---Score at or above which a fuzzy match is offered as a guess but not placed.
M.GUESS = 0.60

---@class sidenote.core.resolve.Outcome
---@field line_start? integer first resolved line, omitted when nothing was placed
---@field line_end? integer last resolved line, inclusive
---@field confidence? number 0..1, defaulting to 0
---@field candidates? integer[] competing start lines, for an ambiguous result
---@field guess? sidenote.Placement best rejected placement

---@param status sidenote.Status
---@param tier string
---@param outcome sidenote.core.resolve.Outcome
---@return sidenote.Resolution
local function result(status, tier, outcome)
    return {
        status = status,
        tier = tier,
        line_start = outcome.line_start,
        line_end = outcome.line_end,
        confidence = outcome.confidence or 0,
        candidates = outcome.candidates,
        guess = outcome.guess,
    }
end

---All start lines at which the record's anchor appears verbatim.
---@param lines string[]
---@param rec sidenote.Annotation
---@return integer[] starts
---@return integer height lines the anchor spans
local function literal_hits(lines, rec)
    local anchor_lines = hash.split(rec.text)
    local height = #anchor_lines
    local first = anchor_lines[1]
    local hits = {}
    for n = 1, #lines - height + 1 do
        if lines[n] == first and hash.slice(lines, n, n + height - 1) == rec.text then
            hits[#hits + 1] = n
        end
    end
    return hits, height
end

---Sort `hits` in place, closest to `hint` first.
---@param hits integer[]
---@param hint integer
local function nearest_first(hits, hint)
    table.sort(hits, function(a, b)
        return math.abs(a - hint) < math.abs(b - hint)
    end)
end

---How many of the captured context sides still surround a candidate placement.
---
---The comparison is exact rather than graded: every candidate already matched
---the anchor verbatim, so anything short of an exact context match is not
---evidence either way.
---@param lines string[]
---@param rec sidenote.Annotation
---@param start integer
---@param height integer
---@return integer matched 0, 1, or 2
local function context_matches(lines, rec, start, height)
    local matched = 0
    local context = record.CONTEXT
    if
        hash.sha256(hash.normalize(hash.slice(lines, start - context, start - 1)))
        == rec.prefix_sha
    then
        matched = matched + 1
    end
    if
        hash.sha256(hash.normalize(hash.slice(lines, start + height, start + height + context - 1)))
        == rec.suffix_sha
    then
        matched = matched + 1
    end
    return matched
end

---Pick the single candidate whose context matches best.
---@param lines string[]
---@param rec sidenote.Annotation
---@param hits integer[]
---@param height integer
---@return integer|nil start nil when no context matched or the best was tied
local function disambiguate(lines, rec, hits, height)
    local best, best_score, tied = nil, -1, false
    for _, n in ipairs(hits) do
        local matched = context_matches(lines, rec, n, height)
        if matched > best_score then
            best, best_score, tied = n, matched, false
        elseif matched == best_score then
            tied = true
        end
    end
    if best and best_score > 0 and not tied then
        return best
    end
    return nil
end

---All start lines whose whitespace-normalized window equals the normalized
---anchor.
---@param lines string[]
---@param rec sidenote.Annotation
---@param height integer
---@return integer[]
local function normalized_hits(lines, rec, height)
    local want = hash.normalize(rec.text)
    local hits = {}
    for n = 1, #lines - height + 1 do
        if hash.normalize(hash.slice(lines, n, n + height - 1)) == want then
            hits[#hits + 1] = n
        end
    end
    return hits
end

---Resolve where `rec`'s anchor sits in `content` now.
---@param rec sidenote.Annotation
---@param content string|nil nil when the file no longer exists
---@return sidenote.Resolution
function M.resolve(rec, content)
    -- No tier ran, so report none rather than naming one that never executed
    if content == nil then
        return result("filegone", "-", {})
    end

    -- A file-scoped note has no text anchor; the file existing is enough
    if rec.scope == "file" then
        return result("attached", "L0", { confidence = 1 })
    end

    -- L0: the file is byte-identical to capture time
    if hash.sha256(content) == rec.file_sha then
        return result("attached", "L0", {
            line_start = rec.line_start,
            line_end = rec.line_end,
            confidence = 1,
        })
    end

    -- A record with no anchor text cannot be searched for, and an honest
    -- orphan beats a ghost attach
    if rec.text == "" then
        return result("orphaned", "-", {})
    end

    local lines = hash.split(content)

    -- L1: the anchor is still exactly where the hint says
    if hash.slice(lines, rec.line_start, rec.line_end) == rec.text then
        return result("attached", "L1", {
            line_start = rec.line_start,
            line_end = rec.line_end,
            confidence = 1,
        })
    end

    -- L2: literal whole-file search. A unique hit wins outright
    local hits, height = literal_hits(lines, rec)
    if #hits == 1 then
        return result("attached", "L2", {
            line_start = hits[1],
            line_end = hits[1] + height - 1,
            confidence = 1,
        })
    end

    -- L3: several verbatim hits; let the captured context break the tie
    if #hits > 1 then
        nearest_first(hits, rec.line_start)
        local best = disambiguate(lines, rec, hits, height)
        if best then
            return result("attached", "L3", {
                line_start = best,
                line_end = best + height - 1,
                confidence = 1,
            })
        end
        return result("ambiguous", "L3", { candidates = hits })
    end

    -- L4: reformat tolerance, under the same uniqueness rule as L2 and L3
    local norm = normalized_hits(lines, rec, height)
    if #norm == 1 then
        return result("attached", "L4", {
            line_start = norm[1],
            line_end = norm[1] + height - 1,
            confidence = 1,
        })
    end
    if #norm > 1 then
        nearest_first(norm, rec.line_start)
        local best = disambiguate(lines, rec, norm, height)
        if best then
            return result("attached", "L4", {
                line_start = best,
                line_end = best + height - 1,
                confidence = 1,
            })
        end
        return result("ambiguous", "L4", { candidates = norm })
    end

    -- L6, not L5: L5 names a treesitter tier this ladder does not implement
    --
    -- Two thresholds, since a guess shown as truth is worse than an honest orphan
    local hit = score.best(lines, rec)
    if hit and hit.score >= M.ACCEPT then
        return result("drifted", "L6", {
            line_start = hit.line_start,
            line_end = hit.line_end,
            confidence = hit.score,
        })
    end
    if hit and hit.score >= M.GUESS then
        return result("orphaned", "L6", { guess = hit })
    end
    return result("orphaned", "L6", {})
end

return M
