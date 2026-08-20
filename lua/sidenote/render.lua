local highlight = require("sidenote.highlight")

---@class sidenote.render.Entry
---@field id string annotation this mark stands for
---@field status sidenote.Status anchor status, deciding the styling
---@field pen? string pen name coloring the ink instead of the status
---@field kind? string note or todo, deciding a healthy anchor's glyph
---@field state? string lifecycle position, checking a done todo's box
---@field hidden? boolean tracked but not drawn, for a narrowed view
---@field summary? string first prose line, nil while the note has none
---@field confidence? number resolver confidence at placement, kept by the tracker
---@field line_start? integer first line, 1-based, absent when unplaced
---@field line_end? integer last line, inclusive
---@field col_start? integer first byte column, 1-based, for a range's exact span
---@field col_end? integer last byte column, inclusive

---@class sidenote.render.Extent
---@field line_start integer first tracked line, 1-based
---@field line_end integer last tracked line, inclusive
---@field col_start integer first byte column, 1-based, or 0 outside range ink
---@field col_end integer last byte column, inclusive, or 0 outside range ink
---@field status sidenote.Status what the resolver concluded at placement
---@field confidence number resolver confidence at placement
---@field invalid boolean whether the tracked text was deleted outright

---@class sidenote.render.Tracker
---@field mark integer extmark id in the tracking namespace
---@field status sidenote.Status what the resolver concluded at placement
---@field confidence number resolver confidence at placement
---@field ranged boolean whether the span carries exact columns

---@class sidenote.render.PaintOpts
---@field style string sign, virt_text, highlight, underline, summary or none
---@field highlight? string the range overlay mode: off, on, always or never
---@field pens? table<string, string> mapping of pen name -> highlight group its ink uses

---Paints resolved annotations into a buffer.
---
---Takes already-resolved entries rather than records, so it never consults the
---store and can be exercised against a scratch buffer.
---@class sidenote.render
local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace("sidenote")

---Where the invisible tracking marks live, apart from the visible ones.
M.TRACK = vim.api.nvim_create_namespace("sidenote.track")

---Live trackers per buffer: annotation id -> the mark following its span.
---@type table<integer, table<string, sidenote.render.Tracker>>
local trackers = {}

---The buffer tick each paint ran at, which is how edits-since are detected.
---@type table<integer, integer>
local ticks = {}

---Groups are defined on first paint rather than at plugin load, so the entry
---point stays free of eager requires.
local defined = false

---@param bufnr integer
function M.clear(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, M.NAMESPACE, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, M.TRACK, 0, -1)
    trackers[bufnr] = nil
    ticks[bufnr] = nil
end

---Whether the buffer has changed since the last paint placed its marks.
---
---This is the moment the marks know more than a fresh resolution would: they
---have followed the edits, while the stored records have not seen them yet.
---False for a buffer never painted.
---@param bufnr integer
---@return boolean
function M.edited(bufnr)
    local tick = ticks[bufnr]
    return tick ~= nil
        and vim.api.nvim_buf_is_valid(bufnr)
        and tick ~= vim.api.nvim_buf_get_changedtick(bufnr)
end

---Per-buffer overrides of the configured highlight default.
---@type table<integer, boolean>
local overrides = {}

---Whether range highlights show in a buffer, under the configured mode.
---@param bufnr integer
---@param mode string|nil off, on, always or never; nil reads as off
---@return boolean
function M.highlighted(bufnr, mode)
    if mode == "always" then
        return true
    end
    if mode == "never" then
        return false
    end
    local override = overrides[bufnr]
    if override ~= nil then
        return override
    end
    return mode == "on"
end

---Whether a toggle, not the config, is what hides this buffer's highlights.
---@param bufnr integer
---@return boolean
function M.suppressed(bufnr)
    return overrides[bufnr] == false
end

---Flip a buffer's range highlights, the way `:set spell!` flips spelling.
---@param bufnr integer
---@param mode string|nil the configured default
---@return boolean|nil shown nil when the mode pins highlights on or off
function M.toggle(bufnr, mode)
    if mode == "always" or mode == "never" then
        return nil
    end
    overrides[bufnr] = not M.highlighted(bufnr, mode)
    return overrides[bufnr]
end

---Where an entry's ink starts: a range's own column, else the line's start.
---@param entry sidenote.render.Entry
---@return integer col 0-based byte column
local function span_start(entry)
    if entry.col_start and entry.col_start > 0 then
        return entry.col_start - 1
    end
    return 0
end

---Where an entry's ink ends: a range's own column, else its last line's text.
---@param bufnr integer
---@param entry sidenote.render.Entry
---@return integer row 0-based
---@return integer col exclusive byte column
local function span_end(bufnr, entry)
    if entry.col_end and entry.col_end > 0 then
        return entry.line_end - 1, entry.col_end
    end
    local last = vim.api.nvim_buf_get_lines(bufnr, entry.line_end - 1, entry.line_end, false)[1]
    return entry.line_end - 1, #(last or "")
end

---@param bufnr integer
---@param entry sidenote.render.Entry
---@param style string
---@param pens table<string, string>|nil pen name -> highlight group
---@return integer|nil col 0-based start column, nil when nothing is drawn
---@return table|nil opts extmark options
local function mark_opts(bufnr, entry, style, pens)
    local group = highlight.GROUPS[entry.status]
    if style == "sign" then
        -- A ranged sign mark repeats its glyph on every covered line, and here
        -- `end_row` is inclusive, unlike a highlight's

        -- A healthy note with no prose dims into the deletion candidate it
        -- is; a hurt anchor keeps its status color, prose or none
        local ink = entry.status == "attached" and not entry.summary and highlight.BARE or group

        -- A healthy todo signs as a box, checked once it is no longer open
        local glyph = highlight.SIGNS[entry.status]
        if entry.status == "attached" and entry.kind == "todo" then
            glyph = entry.state == "open" and highlight.TODO.open or highlight.TODO.done
        end
        return 0,
            {
                end_row = entry.line_end - 1,
                sign_text = glyph,
                sign_hl_group = ink,
            }
    end
    if style == "virt_text" then
        return 0,
            { virt_text = { { highlight.SIGNS[entry.status], group } }, virt_text_pos = "eol" }
    end
    if style == "summary" then
        -- The ambient reading mode: prose line one sits at end of line, in
        -- the note's own pen when it carries one
        local pen = entry.pen and pens and pens[entry.pen]
        local text = entry.summary
        if text and #text > 60 then
            text = text:sub(1, 60) .. "…"
        end
        return 0,
            {
                virt_text = {
                    text and { text, pen or highlight.PROSE } or { "(no prose)", highlight.BARE },
                },
                virt_text_pos = "eol",
            }
    end

    -- Ink over the text and only the text, the way a marker pen reads: exact
    -- columns for a range, through the last line's end otherwise
    if style == "highlight" or style == "underline" then
        -- A pen the caller no longer knows degrades to the status ink
        local pen = entry.pen and pens and pens[entry.pen]
        local end_row, end_col = span_end(bufnr, entry)
        return span_start(entry),
            {
                end_row = end_row,
                end_col = end_col,
                hl_group = style == "highlight" and (pen or highlight.MARKS[entry.status])
                    or highlight.UNDERLINES[entry.status],
            }
    end
    return nil, nil
end

---Place the invisible mark that follows a span through edits.
---
---Default gravity is deliberate: text typed strictly inside the span grows
---it, text typed at either edge stays outside, and deleting the whole span
---marks it invalid rather than leaving a zero-width ghost.
---@param bufnr integer
---@param entry sidenote.render.Entry
local function track(bufnr, entry)
    local end_row, end_col = span_end(bufnr, entry)
    local mark = vim.api.nvim_buf_set_extmark(
        bufnr,
        M.TRACK,
        entry.line_start - 1,
        span_start(entry),
        { end_row = end_row, end_col = end_col, invalidate = true }
    )
    trackers[bufnr][entry.id] = {
        mark = mark,
        status = entry.status,
        confidence = entry.confidence or (entry.status == "attached" and 1 or 0),
        ranged = (entry.col_start or 0) > 0,
    }
end

---What a placed annotation's mark covers right now, or nil when unplaced.
---
---Between one paint and the next the mark has followed every edit, so this
---is where the annotation truly is while the buffer changes underneath it.
---`invalid` means the tracked text was deleted outright — a cut headed for a
---paste looks exactly like that, so the caller falls back to the resolver
---rather than trusting a collapsed span.
---@param bufnr integer
---@param id string
---@return sidenote.render.Extent|nil
function M.extent(bufnr, id)
    local tracked = trackers[bufnr] and trackers[bufnr][id]
    if not tracked or not vim.api.nvim_buf_is_valid(bufnr) then
        return nil
    end
    local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, M.TRACK, tracked.mark, {
        details = true,
    })
    if #mark == 0 then
        return nil
    end

    local row, col, details = mark[1], mark[2], mark[3]
    -- An end resting at column 0 covers nothing on its own line
    local line_end = details.end_row + 1
    if details.end_row > row and details.end_col == 0 then
        line_end = details.end_row
    end
    return {
        line_start = row + 1,
        line_end = line_end,
        col_start = tracked.ranged and col + 1 or 0,
        col_end = tracked.ranged and details.end_col or 0,
        status = tracked.status,
        confidence = tracked.confidence,
        invalid = details.invalid == true or (details.end_row == row and details.end_col <= col),
    }
end

---Clear and repaint every entry, returning how many were actually placed.
---
---Every positioned entry gets a tracker whatever the style, so a save can
---re-baseline to the edited span even when nothing is drawn.
---@param bufnr integer
---@param entries sidenote.render.Entry[]
---@param opts sidenote.render.PaintOpts
---@return integer placed
function M.paint(bufnr, entries, opts)
    if not defined then
        highlight.setup()
        defined = true
    end

    M.clear(bufnr)
    trackers[bufnr] = {}
    ticks[bufnr] = vim.api.nvim_buf_get_changedtick(bufnr)

    -- The overlay repeats the highlight style on top of the configured one,
    -- so it adds nothing when highlight already is the style
    local overlay = opts.style ~= "highlight"
        and opts.style ~= "none"
        and M.highlighted(bufnr, opts.highlight)

    local count = vim.api.nvim_buf_line_count(bufnr)
    local placed = 0
    for _, entry in ipairs(entries) do
        -- An unplaced or out-of-range entry is skipped rather than clamped:
        -- clamping is how an annotation ends up pointing at unrelated code
        if entry.line_start and entry.line_end and entry.line_end <= count then
            -- Tracked even when a narrowed view hides it: invisibility must
            -- not cost a note its save-time truth
            track(bufnr, entry)
            if opts.style ~= "none" and not entry.hidden then
                local col, mark = mark_opts(bufnr, entry, opts.style, opts.pens)
                if mark then
                    mark.priority = highlight.PRIORITIES[entry.status]
                    vim.api.nvim_buf_set_extmark(
                        bufnr,
                        M.NAMESPACE,
                        entry.line_start - 1,
                        col,
                        mark
                    )
                    placed = placed + 1
                end
                if overlay then
                    local ink, range = mark_opts(bufnr, entry, "highlight", opts.pens)
                    range.priority = highlight.PRIORITIES[entry.status]
                    vim.api.nvim_buf_set_extmark(
                        bufnr,
                        M.NAMESPACE,
                        entry.line_start - 1,
                        ink,
                        range
                    )
                end
            end
        end
    end
    return placed
end

return M
