local hash = require("sidenote.core.hash")

---@class sidenote.Vcs
---@field kind "git"|"jj" version control the annotated file sits under
---@field commit string commit id at capture, as provenance only
---@field dirty boolean whether the file had uncommitted changes at capture

---@class sidenote.Annotation
---@field id string ULID, sorting by creation time
---@field schema integer on-disk format version of this record
---@field kind "note"|"todo" whether the note is information or a request to act
---@field state "open"|"answered"|"resolved"|"wontfix"|"archived" lifecycle position
---@field project_key string identity of the project the path is relative to
---@field path string annotated file, relative to the project root
---@field scope "file"|"lines"|"range" what the annotation covers
---@field line_start integer first annotated line, 1-based, or 0 for file scope
---@field line_end integer last annotated line, inclusive
---@field col_start integer first annotated byte column, 1-based, or 0 outside range scope
---@field col_end integer last annotated byte column, inclusive
---@field text string verbatim anchored bytes, or "" for file scope
---@field prefix string verbatim lines immediately above the anchor
---@field suffix string verbatim lines immediately below the anchor
---@field text_sha string hash of the anchored bytes
---@field norm_sha string hash of the anchored bytes with whitespace collapsed
---@field prefix_sha string hash of the normalized lines above the anchor
---@field suffix_sha string hash of the normalized lines below the anchor
---@field file_sha string hash of the whole file at capture
---@field symbol string enclosing named symbol, when one was known
---@field ts_path string enclosing treesitter node path, when one was known
---@field vcs sidenote.Vcs|nil provenance only, never used for resolution
---@field captured string ISO-8601 instant the annotation was written
---@field verified string ISO-8601 instant the anchor last resolved exactly

---@class sidenote.core.record.Opts
---@field id string ULID for the new annotation
---@field project_key string identity of the project the path is relative to
---@field path string annotated file, relative to the project root
---@field content string full text of the annotated file
---@field now string ISO-8601 capture instant
---@field scope? "file"|"lines"|"range" defaults to range
---@field line_start? integer required outside file scope
---@field line_end? integer required outside file scope
---@field col_start? integer defaults to 1 in range scope
---@field col_end? integer defaults to 1 in range scope
---@field kind? "note"|"todo" defaults to note
---@field symbol? string enclosing named symbol
---@field ts_path? string enclosing treesitter node path
---@field vcs? sidenote.Vcs provenance captured by the store

---@class sidenote.core.record
local M = {}

---Current on-disk schema version.
M.SCHEMA = 1

---Lines of surrounding context captured on each side of the anchor.
M.CONTEXT = 3

local SCOPES = { file = true, lines = true, range = true }

---Whether the note is information or a request to act.
---
---Exported so the browser validates the column it renders against the same set
---this module writes.
---@type table<string, boolean>
M.KINDS = { note = true, todo = true }

---Lifecycle positions a record may hold.
---@type table<string, boolean>
M.STATES = {
    open = true,
    -- Reserved for the future agent `answer` verb; nothing produces it yet
    answered = true,
    resolved = true,
    wontfix = true,
    archived = true,
}

---@param opts sidenote.core.record.Opts
---@return sidenote.Annotation
function M.capture(opts)
    local lines = hash.split(opts.content)
    local scope = opts.scope or "range"
    local whole_file = scope == "file"
    local line_start = whole_file and 0 or opts.line_start
    local line_end = whole_file and 0 or opts.line_end
    local text = whole_file and "" or hash.slice(lines, line_start, line_end)
    local prefix = whole_file and "" or hash.slice(lines, line_start - M.CONTEXT, line_start - 1)
    local suffix = whole_file and "" or hash.slice(lines, line_end + 1, line_end + M.CONTEXT)

    return {
        id = opts.id,
        schema = M.SCHEMA,
        kind = opts.kind or "note",
        state = "open",
        project_key = opts.project_key,
        path = opts.path,
        scope = scope,
        line_start = line_start,
        line_end = line_end,
        -- Columns belong to `range` scope alone: the grammar derives scope from
        -- their absence, so a 1 here would render `lines` as a range
        col_start = scope == "range" and (opts.col_start or 1) or 0,
        col_end = scope == "range" and (opts.col_end or 1) or 0,
        text = text,
        -- Kept verbatim, not only as a hash: the fuzzy tier grades context by
        -- similarity, and a hash can only answer same-or-different
        prefix = prefix,
        suffix = suffix,
        text_sha = hash.sha256(text),
        norm_sha = hash.sha256(hash.normalize(text)),
        prefix_sha = hash.sha256(hash.normalize(prefix)),
        suffix_sha = hash.sha256(hash.normalize(suffix)),
        file_sha = hash.sha256(opts.content),
        symbol = opts.symbol or "",
        ts_path = opts.ts_path or "",
        vcs = opts.vcs,
        captured = opts.now,
        verified = opts.now,
    }
end

---@class sidenote.core.record.ReanchorOpts
---@field path string annotated file, relative to the project root
---@field content string full text of the file the annotation now points into
---@field scope "file"|"lines"|"range" what the annotation now covers
---@field now string ISO-8601 instant the anchor was re-captured
---@field line_start? integer required outside file scope
---@field line_end? integer required outside file scope
---@field col_start? integer defaults to 1 in range scope
---@field col_end? integer defaults to 1 in range scope

---Re-capture a record's anchor at a location its owner asserted.
---
---Takes the file as it is now rather than searching it for the old anchor
---text: someone editing a location is telling us where the annotation belongs,
---which beats any inference the resolver could make. That is what makes this
---the manual repair for a cross-file move.
---
---Identity and everything the user owns survive — `id`, `kind`, `state` and
---`captured`. The anchor, its context, every hash and `verified` are refreshed.
---`symbol` and `ts_path` are cleared, since both described the old location.
---@param rec sidenote.Annotation
---@param opts sidenote.core.record.ReanchorOpts
---@return sidenote.Annotation
function M.reanchor(rec, opts)
    local fresh = M.capture({
        id = rec.id,
        project_key = rec.project_key,
        path = opts.path,
        content = opts.content,
        scope = opts.scope,
        line_start = opts.line_start,
        line_end = opts.line_end,
        col_start = opts.col_start,
        col_end = opts.col_end,
        kind = rec.kind,
        vcs = rec.vcs,
        now = opts.now,
    })
    fresh.state = rec.state
    fresh.captured = rec.captured
    return fresh
end

---@param rec sidenote.Annotation
---@return boolean ok
---@return string|nil err
function M.validate(rec)
    if type(rec.id) ~= "string" or rec.id == "" then
        return false, "id: expected a non-empty string"
    end
    if type(rec.project_key) ~= "string" or rec.project_key == "" then
        return false, "project_key: expected a non-empty string"
    end
    if type(rec.path) ~= "string" or rec.path == "" then
        return false, "path: expected a non-empty string"
    end
    if not SCOPES[rec.scope] then
        return false, ("scope: expected file|lines|range, got %s"):format(tostring(rec.scope))
    end
    if not M.KINDS[rec.kind] then
        return false, ("kind: expected note|todo, got %s"):format(tostring(rec.kind))
    end
    if not M.STATES[rec.state] then
        return false,
            ("state: expected open|answered|resolved|wontfix|archived, got %s"):format(
                tostring(rec.state)
            )
    end
    if type(rec.line_start) ~= "number" or type(rec.line_end) ~= "number" then
        return false, "line_start/line_end: expected numbers"
    end
    if rec.scope ~= "file" and rec.line_start < 1 then
        return false,
            ("line_start: must be >= 1 for scope %s, got %d"):format(rec.scope, rec.line_start)
    end
    if rec.line_end < rec.line_start then
        return false,
            ("line_end: must be >= line_start (%d < %d)"):format(rec.line_end, rec.line_start)
    end
    return true, nil
end

---Serialize a record for its `.metadata.json` sidecar.
---@param rec sidenote.Annotation
---@return string
function M.encode(rec)
    return vim.json.encode(rec)
end

---@param json string
---@return sidenote.Annotation|nil
---@return string|nil err
function M.decode(json)
    local ok, decoded = pcall(vim.json.decode, json)
    if not ok then
        return nil, ("malformed JSON: %s"):format(tostring(decoded))
    end
    if type(decoded) ~= "table" or vim.islist(decoded) then
        return nil, "expected a JSON object"
    end
    return decoded, nil
end

return M
