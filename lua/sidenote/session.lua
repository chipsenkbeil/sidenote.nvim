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
---The only constructor for `sidenote.session.Entry`: build one here rather
---than by hand, so a field the type gains reaches every entry.
---@param root string store root the record was read from
---@param rec sidenote.Annotation
---@param resolution sidenote.Resolution
---@return sidenote.session.Entry
function M.entry(root, rec, resolution)
    return {
        id = rec.id,
        status = resolution.status,
        pen = rec.pen,
        kind = rec.kind,
        state = rec.state,
        confidence = resolution.confidence,
        line_start = resolution.line_start,
        line_end = resolution.line_end,
        -- Columns travel only for a range, whose ink covers its exact span;
        -- a live resolution carries its own, tracked through the edits
        col_start = rec.scope == "range" and (resolution.col_start or rec.col_start) or nil,
        col_end = rec.scope == "range" and (resolution.col_end or rec.col_end) or nil,
        root = root,
        record = rec,
        resolution = resolution,
    }
end

---Read the mark tracking `rec` as a resolution.
---
---A collapsed or missing mark returns nil, sending the caller back to the
---real resolver.
---@param bufnr integer
---@param rec sidenote.Annotation
---@return sidenote.Resolution|nil
local function live_resolution(bufnr, rec)
    local live = rec.scope ~= "file" and render.extent(bufnr, rec.id) or nil
    if not live or live.invalid then
        return nil
    end
    return {
        status = live.status,
        line_start = live.line_start,
        line_end = live.line_end,
        col_start = live.col_start > 0 and live.col_start or nil,
        col_end = live.col_end > 0 and live.col_end or nil,
        confidence = live.confidence,
        tier = "live",
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

    -- Painted marks have tracked every edit since the paint; re-resolving
    -- from stored content would fight the edit in progress
    local editing = render.edited(bufnr)

    local entries, seen = {}, {}
    for _, root in ipairs(roots) do
        for _, id in ipairs(store.ids(root)) do
            if not seen[id] then
                local rec = store.read(root, id)
                if rec and rec.path == wanted then
                    seen[id] = true
                    local resolution = editing and live_resolution(bufnr, rec)
                        or resolve.resolve(rec, target.content)
                    local entry = M.entry(root, rec, resolution)
                    entry.summary = store.summary(root, rec.id, cfg.filetype)
                    entries[#entries + 1] = entry
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        return (a.line_start or math.huge) < (b.line_start or math.huge)
    end)
    return entries
end

---What every surface currently shows; empty shows everything.
---@type sidenote.Filter
local view = {}

---Narrow what is painted and visited, everywhere at once.
---
---A display choice, not a data one: `entries` stays complete, so nothing
---reading a note's data silently loses one. Every loaded annotatable buffer
---repaints, and `vim.g.sidenote_state.show` mirrors the narrowing for
---statuslines.
---@param filter sidenote.Filter|nil nil or {} widens back to everything
---@return sidenote.Filter showing
function M.view(filter)
    view = filter or {}

    local parts = {}
    for _, key in ipairs({ "kind", "state", "status", "path" }) do
        if view[key] then
            parts[#parts + 1] = key .. "=" .. view[key]
        end
    end
    local state = vim.g.sidenote_state or {}
    state.show = table.concat(parts, " ")
    vim.g.sidenote_state = state

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            M.refresh(bufnr)
        end
    end
    return view
end

---Report the narrowing in force.
---@return sidenote.Filter
function M.viewing()
    return view
end

---Resolve and repaint a buffer, returning how many marks were placed.
---
---Only entries passing the `view` narrowing are painted; the rest exist,
---unpainted, until the view widens again.
---@param bufnr integer
---@param cfg? sidenote.Config
---@return integer placed
function M.refresh(bufnr, cfg)
    cfg = cfg or config.get()

    -- Marks in an unannotatable buffer belong to whoever painted them
    if not buffer.target(bufnr, { scope = "file" }) then
        return 0
    end

    local survives = require("sidenote.filter").survives
    local entries = M.entries(bufnr, cfg)

    -- Hidden, not dropped: the tracker still places, so a narrowed view
    -- never costs a note its live extent
    for _, entry in ipairs(entries) do
        entry.hidden = not survives(entry, view)
    end

    return render.paint(bufnr, entries, {
        style = cfg.indicator.style,
        highlight = cfg.indicator.highlight,
        pens = cfg.pens,
    })
end

---@class sidenote.session.SaveOpts
---@field content string full text of the saved buffer
---@field file_sha string hash of that text
---@field now string ISO-8601 instant of the save

---Decide what a save writes for one annotation, or nil to leave it alone.
---
---Two sources, tried in order:
---
---1. A live mark placed on an exact anchor. It has tracked the user's own
---   edits since the last paint, so its extent is an assertion, not a guess:
---   the record re-baselines there even when the text inside was rewritten.
---2. The resolver. At the stored position only `file_sha` and `verified`
---   refresh, keeping the whole-file fast path warm; attached elsewhere, the
---   code legitimately moved and everything re-captures at the new position,
---   so drift stops compounding.
---
---Anything else returns nil: a good anchor is never overwritten with a
---guess, which includes the mark of a placement that was itself a guess.
---@param bufnr integer
---@param entry sidenote.session.Entry
---@param opts sidenote.session.SaveOpts
---@return sidenote.Annotation|nil
local function rebaseline(bufnr, entry, opts)
    local rec = entry.record
    local live = rec.scope ~= "file" and render.extent(bufnr, rec.id) or nil
    if live and not live.invalid and live.status == "attached" then
        return record.reanchor(rec, {
            path = rec.path,
            content = opts.content,
            scope = rec.scope,
            line_start = live.line_start,
            line_end = live.line_end,
            col_start = live.col_start > 0 and live.col_start or nil,
            col_end = live.col_end > 0 and live.col_end or nil,
            now = opts.now,
        })
    end

    local res = entry.resolution
    if res.status ~= "attached" then
        return nil
    end
    local moved = rec.scope ~= "file"
        and (res.line_start ~= rec.line_start or res.line_end ~= rec.line_end)
    if moved then
        return record.reanchor(rec, {
            path = rec.path,
            content = opts.content,
            scope = rec.scope,
            line_start = res.line_start,
            line_end = res.line_end,
            col_start = rec.col_start,
            col_end = rec.col_end,
            now = opts.now,
        })
    end
    local fresh = vim.deepcopy(rec)
    fresh.file_sha = opts.file_sha
    fresh.verified = opts.now
    return fresh
end

---Write anchors back after their buffer was saved.
---
---Only annotations whose file actually changed are touched, and one is
---left untouched whenever the buffer cannot say where its code went: a
---good anchor is never overwritten with a guess.
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
    local save = {
        content = target.content,
        file_sha = hash.sha256(target.content),
        now = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }

    local written = 0
    for _, entry in ipairs(entries) do
        if entry.record.file_sha ~= save.file_sha then
            local fresh = rebaseline(bufnr, entry, save)
            if fresh and store.update(entry.root, fresh) then
                written = written + 1
            end
        end
    end
    return written
end

return M
