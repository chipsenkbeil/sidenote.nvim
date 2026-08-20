local config = require("sidenote.config")
local highlight = require("sidenote.highlight")
local location = require("sidenote.location")
local store = require("sidenote.store")
local window = require("sidenote.window")

---Opens a note's prose for writing.
---
---Opens the real file rather than a scratch copy, so the user's own filetype
---plugins apply and saving lands exactly where the store expects it.
---@class sidenote.editor
local M = {}

---Where the context header's virtual lines live.
M.NAMESPACE = vim.api.nvim_create_namespace("sidenote.context")

---Most display columns a header snippet line may take.
local SNIPPET_MAX = 60

---Most snippet lines the header shows.
local SNIPPET_LINES = 3

---@type integer|nil
local current

---@return integer|nil winid
function M.winid()
    if current and vim.api.nvim_win_is_valid(current) then
        return current
    end
    return nil
end

---@class sidenote.editor.Note
---@field root string store root the annotation lives in
---@field id string annotation whose prose to open
---@field record? sidenote.Annotation full record, which is what earns a context header
---@field resolution? sidenote.Resolution where the note sits now
---@field status? sidenote.Status anchor status at the last resolution
---@field line_start? integer first line the note covers now
---@field line_end? integer last line, inclusive
---@field source? integer loaded buffer of the annotated file, for the snippet
---@field config? sidenote.Config configuration, for pens and the ink style

---Trim a snippet line and clip it to the header's width.
---@param text string
---@return string
local function clipped(text)
    text = vim.trim(text)
    if vim.fn.strdisplaywidth(text) > SNIPPET_MAX then
        text = vim.fn.strcharpart(text, 0, SNIPPET_MAX) .. "…"
    end
    return text
end

---The winbar line naming the open note: its identity, pinned.
---
---Location, kind and state on the winbar's own background, then a swatch
---drawn in the note's actual ink — the pen's wash, the status mark for a
---penless note, or a squiggle when the configured style is `underline` —
---and the anchor status with its confidence whenever it is short of exact.
---@param entry sidenote.editor.Note
---@return string winbar statusline-format text
function M.headline(entry)
    local rec = assert(entry.record)
    local cfg = entry.config or config.get()
    local bar = "%#" .. highlight.WINBAR .. "#"

    local parts = {
        bar,
        " ",
        location.format(rec):gsub("%%", "%%%%"),
        "  ",
        rec.kind,
        " · ",
        rec.state,
        " · ",
    }
    if rec.pen then
        parts[#parts + 1] = rec.pen .. " "
    end
    local status = entry.status or "attached"
    if cfg.indicator.style == "underline" then
        parts[#parts + 1] = "%#" .. highlight.UNDERLINES[status] .. "#~~~"
    else
        local ink = rec.pen and (cfg.pens or {})[rec.pen] or highlight.MARKS[status]
        parts[#parts + 1] = "%#" .. ink .. "#■"
    end
    parts[#parts + 1] = bar

    if status ~= "attached" then
        local label = status
        local confidence = entry.resolution and entry.resolution.confidence
        if confidence and confidence > 0 and confidence < 1 then
            label = ("%s %.2f"):format(label, confidence)
        end
        parts[#parts + 1] = " · %#" .. highlight.GROUPS[status] .. "#" .. label .. bar
    end
    return table.concat(parts)
end

---The quoted snippet shown above a note's prose, identity-free.
---
---The code the note covers, each line under its own source line number and
---behind a `│`, closed by a divider so the quote never bleeds into prose.
---Read from `source` when it is loaded — the code as it is now — else from
---the stored anchor text. A drifted note keeps its stored first line on a
---`was:` row, since the snippet is then only the resolver's best idea. A
---file-wide note has no snippet at all; the winbar carries its identity.
---@param entry sidenote.editor.Note
---@param source integer|nil loaded buffer of the annotated file
---@return {[1]: string, [2]: string}[][] lines chunk lines, possibly empty
function M.header(entry, source)
    local rec = assert(entry.record)
    if rec.scope == "file" then
        return {}
    end

    local live = source
            and vim.api.nvim_buf_is_valid(source)
            and vim.api.nvim_buf_is_loaded(source)
            and entry.line_start
            and vim.api.nvim_buf_get_lines(source, entry.line_start - 1, entry.line_end, false)
        or nil
    local body = live or vim.split(rec.text, "\n")
    local first = (live and entry.line_start or rec.line_start) or 1
    local width = #tostring(first + math.min(#body, SNIPPET_LINES) - 1)

    local lines = {}
    for i = 1, math.min(#body, SNIPPET_LINES) do
        lines[#lines + 1] = {
            { ("%" .. width .. "d │ "):format(first + i - 1), "LineNr" },
            { clipped(body[i]), highlight.CONTEXT },
        }
    end
    if #body > SNIPPET_LINES then
        lines[#lines + 1] = { { (" "):rep(width) .. " │ ⋯", "LineNr" } }
    end
    if live and entry.status == "drifted" then
        lines[#lines + 1] = {
            { (" "):rep(width) .. " │ ", "LineNr" },
            { "was: ", highlight.GROUPS.drifted },
            { clipped(vim.split(rec.text, "\n")[1]), highlight.CONTEXT },
        }
    end
    lines[#lines + 1] = { { ("─"):rep(48), highlight.CONTEXT } }
    return lines
end

---Paint the header above the prose and pin the identity into the winbar.
---
---The virtual lines sit above row 0, which a window opened at the very top
---does not show until filler rows are asked for; `topfill` is that ask. The
---winbar alone carries the identity, because virtual lines scroll away with
---line 1 in a note longer than its window.
---@param bufnr integer prose buffer
---@param winid integer editor window
---@param entry sidenote.editor.Note
local function decorate(bufnr, winid, entry)
    local lines = M.header(entry, entry.source)
    vim.api.nvim_buf_clear_namespace(bufnr, M.NAMESPACE, 0, -1)
    if #lines > 0 then
        vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, 0, 0, {
            virt_lines = lines,
            virt_lines_above = true,
        })
    end

    vim.api.nvim_set_option_value("winbar", M.headline(entry), { win = winid, scope = "local" })
    vim.api.nvim_win_call(winid, function()
        vim.fn.winrestview({ topline = 1, topfill = #lines })
    end)
end

---Open a note, returning the window showing it.
---
---The `toggle` style behaves as `split`, except that asking for the note
---already on show puts it away instead and returns nil.
---@param entry sidenote.editor.Note
---@param opts sidenote.EditorConfig
---@param filetype string
---@return integer|nil winid nil when a toggle closed the note
function M.open(entry, opts, filetype)
    local path = store.prose_target(entry.root, entry.id, filetype)

    if opts.style == "toggle" then
        local shown = M.winid()
        local name = shown and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(shown))
        if name and (vim.uv.fs_realpath(name) or name) == (vim.uv.fs_realpath(path) or path) then
            window.close(shown)
            current = nil
            return nil
        end
    end

    local bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
    -- From the file, not the parameter: a note written under an earlier
    -- `filetype` setting keeps the highlighting its extension names
    vim.bo[bufnr].filetype = vim.fn.fnamemodify(path, ":e")

    local winid = M.winid()
    if winid then
        vim.api.nvim_win_set_buf(winid, bufnr)
        if opts.focus then
            vim.api.nvim_set_current_win(winid)
        end
    else
        winid = window.open(bufnr, {
            style = opts.style == "toggle" and "split" or opts.style,
            position = opts.position,
            size = opts.size,
            focus = opts.focus,
        })
        current = winid
    end

    if entry.record then
        decorate(bufnr, winid, entry)
    end
    return winid
end

return M
