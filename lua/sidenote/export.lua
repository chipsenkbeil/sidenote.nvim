local project = require("sidenote.store.project")
local scan = require("sidenote.scan")
local store = require("sidenote.store")

---@class sidenote.export.Record
---@field id string ULID of the annotation
---@field kind "note"|"todo" whether the note is information or a request to act
---@field state "open"|"resolved"|"wontfix"|"archived" lifecycle position, human-owned
---@field path string annotated file, relative to the project root
---@field status sidenote.Status what the resolver concluded
---@field change string|nil jj change id stamped at capture, absent outside jj
---@field commit string|nil commit id stamped at capture, absent outside a repo
---@field confidence number 0..1, and 1 for the exact tiers
---@field code_no_longer_exists boolean true when no position is offered
---@field prose string the note itself, verbatim
---@field anchor_text string the code the note was written against
---@field line_start integer|nil first line, absent whenever the gate withheld it
---@field line_end integer|nil last line inclusive, absent alongside line_start

---@class sidenote.export.Document
---@field schema integer format version of this document
---@field project_key string identity of the project the paths are relative to
---@field generated string ISO-8601 instant the document was produced
---@field annotations sidenote.export.Record[] every annotation, sorted

---@class sidenote.export.Opts
---@field path string a file inside the project, or the project root itself
---@field config sidenote.Config resolved configuration
---@field now? string ISO-8601 stamp for the document, defaults to the clock

---What an agent is allowed to read, and on what terms.
---@class sidenote.export
local M = {}

---Format version of an exported document.
M.SCHEMA = 1

---Statuses that export with a resolved position.
---
---Everything else exports its original anchor text and no line numbers at all.
---A naive fuzzy match measured 8% precision, so a guessed position presented as
---a location would point an agent at code that was never the subject.
---@type table<sidenote.Status, boolean>
M.PLACED = {
    attached = true,
    drifted = true,
}

---Turn one resolved annotation into the record an agent sees.
---@param entry sidenote.session.Entry
---@param prose string the note's text, as stored
---@return sidenote.export.Record
function M.entry(entry, prose)
    local rec = entry.record
    local placed = M.PLACED[entry.status] or false
    return {
        id = rec.id,
        kind = rec.kind,
        state = rec.state,
        path = rec.path,
        status = entry.status,
        change = rec.vcs and rec.vcs.change or nil,
        commit = rec.vcs and rec.vcs.commit or nil,
        confidence = entry.resolution.confidence,
        code_no_longer_exists = not placed,
        prose = prose,
        anchor_text = rec.text,
        line_start = placed and entry.line_start or nil,
        line_end = placed and entry.line_end or nil,
    }
end

---The note's prose, trailing blank lines dropped, or empty when it has none.
---@param entry sidenote.session.Entry
---@param filetype string
---@return string
local function prose_of(entry, filetype)
    local text = store.prose(entry.root, entry.id, filetype) or ""
    return (text:gsub("\n+$", ""))
end

---Every annotation in a project, gated and ordered.
---@param opts sidenote.export.Opts
---@return sidenote.export.Document
function M.project(opts)
    local entries = scan.project({ path = opts.path, config = opts.config })

    local annotations = {}
    for i, entry in ipairs(entries) do
        annotations[i] = M.entry(entry, prose_of(entry, opts.config.filetype))
    end

    local root = project.root(opts.path)
    return {
        schema = M.SCHEMA,
        project_key = project.key(root or opts.path),
        generated = opts.now or os.date("!%Y-%m-%dT%H:%M:%SZ"),
        annotations = annotations,
    }
end

return M
