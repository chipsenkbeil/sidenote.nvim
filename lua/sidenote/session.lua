local buffer = require("sidenote.buffer")
local config = require("sidenote.config")
local hash = require("sidenote.core.hash")
local project = require("sidenote.store.project")
local record = require("sidenote.core.record")
local render = require("sidenote.render")
local resolve = require("sidenote.core.resolve")
local store = require("sidenote.store")
local strategy = require("sidenote.store.strategy")

---@class sidenote.session.Entry: sidenote.render.Entry
---@field root string store root the record came from
---@field record sidenote.Annotation the stored record
---@field resolution sidenote.Resolution what the resolver concluded

---Ties a buffer to the annotations that target it.
---@class sidenote.session
local M = {}

---Bind a record, the store it came from, and what the resolver concluded.
---
---The only constructor for `sidenote.session.Entry`, so a field added to that
---type cannot be forgotten by one of the places that build them.
---@param root string store root the record was read from
---@param rec sidenote.Annotation
---@param resolution sidenote.Resolution
---@return sidenote.session.Entry
function M.entry(root, rec, resolution)
    return {
        id = rec.id,
        status = resolution.status,
        line_start = resolution.line_start,
        line_end = resolution.line_end,
        root = root,
        record = rec,
        resolution = resolution,
    }
end

---Resolve every annotation targeting a buffer, against the buffer's current
---text rather than the file on disk, so unsaved edits are accounted for.
---
---A buffer that resolves to no store, or has no name, yields an empty list: a
---file simply may not be annotatable, and that is not an error worth raising
---on every buffer the user opens.
---@param bufnr integer
---@param cfg? sidenote.Config
---@return sidenote.session.Entry[]
function M.entries(bufnr, cfg)
    cfg = cfg or config.get()

    local target = buffer.target(bufnr, { scope = "file" })
    if not target then
        return {}
    end

    local roots = strategy.resolve(target.path, cfg)
    if not roots then
        return {}
    end

    local project_root = project.root(target.path)
    local wanted = project_root and project.relative(project_root, target.path) or target.path

    local entries, seen = {}, {}
    for _, root in ipairs(roots) do
        for _, id in ipairs(store.ids(root)) do
            if not seen[id] then
                local rec = store.read(root, id)
                if rec and rec.path == wanted then
                    seen[id] = true
                    entries[#entries + 1] = M.entry(root, rec, resolve.resolve(rec, target.content))
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        return (a.line_start or math.huge) < (b.line_start or math.huge)
    end)
    return entries
end

---Resolve and repaint a buffer, returning how many marks were placed.
---@param bufnr integer
---@param cfg? sidenote.Config
---@return integer placed
function M.refresh(bufnr, cfg)
    cfg = cfg or config.get()
    -- An unannotatable buffer keeps whatever marks its owner painted; the
    -- browser draws its status gutter into this same namespace
    if not buffer.target(bufnr, { scope = "file" }) then
        return 0
    end
    return render.paint(bufnr, M.entries(bufnr, cfg), cfg.indicator)
end

---Write verified anchors back after their buffer was saved.
---
---Per attached annotation, one of two things:
---
---1. If it sits at its stored position, only `file_sha` and `verified` are
---   refreshed, keeping the whole-file fast path warm.
---2. If it attached somewhere else, the code legitimately moved: hints, the
---   anchor text, its context and every hash are re-captured at the new
---   position, so drift stops compounding.
---
---Anything the resolver could not attach is never written; a good anchor is
---not overwritten with a guess. Only changed records are persisted.
---@param bufnr integer
---@param cfg? sidenote.Config
---@return integer written how many records were persisted
function M.written(bufnr, cfg)
    cfg = cfg or config.get()
    local entries = M.entries(bufnr, cfg)
    if #entries == 0 then
        return 0
    end

    local target = buffer.target(bufnr, { scope = "file" })
    if not target then
        return 0
    end
    local file_sha = hash.sha256(target.content)
    local now = os.date("!%Y-%m-%dT%H:%M:%SZ")

    local written = 0
    for _, entry in ipairs(entries) do
        local rec = entry.record
        local res = entry.resolution
        -- An unchanged file needs nothing; anything short of attached is a
        -- guess, and a guess never overwrites a good anchor
        if res.status == "attached" and rec.file_sha ~= file_sha then
            local moved = rec.scope ~= "file"
                and (res.line_start ~= rec.line_start or res.line_end ~= rec.line_end)
            local fresh
            if moved then
                fresh = record.reanchor(rec, {
                    path = rec.path,
                    content = target.content,
                    scope = rec.scope,
                    line_start = res.line_start,
                    line_end = res.line_end,
                    col_start = rec.col_start,
                    col_end = rec.col_end,
                    now = now,
                })
            else
                fresh = vim.deepcopy(rec)
                fresh.file_sha = file_sha
                fresh.verified = now
            end
            if store.update(entry.root, fresh) then
                written = written + 1
            end
        end
    end
    return written
end

return M
