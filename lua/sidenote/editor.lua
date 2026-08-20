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

---Build the context header shown above a note's prose.
---
---One line of identity — location, kind, state, pen, and the anchor status
---whenever it is short of exact — then a short snippet of the annotated
---code. The snippet reads `source` when it is loaded, so it shows the code
---as it is now; without one it falls back to the stored anchor text. A
---drifted note keeps its stored text visible on a `was:` line, since what
---the snippet shows is then only the resolver's best idea.
---@param entry sidenote.editor.Note
---@param source integer|nil loaded buffer of the annotated file
---@return {[1]: string, [2]: string}[][] lines chunk lines, never empty
function M.header(entry, source)
    local rec = assert(entry.record)
    local res = entry.resolution

    local first = { { location.format(rec), highlight.CONTEXT } }
    for _, part in ipairs({ rec.kind, rec.state, rec.pen }) do
        first[#first + 1] = { " · " .. part, highlight.CONTEXT }
    end
    if entry.status and entry.status ~= "attached" then
        local label = entry.status
        local confidence = res and res.confidence
        if confidence and confidence > 0 and confidence < 1 then
            label = ("%s %.2f"):format(label, confidence)
        end
        first[#first + 1] = { " · " .. label, highlight.GROUPS[entry.status] }
    end
    local lines = { first }

    if rec.scope == "file" then
        return lines
    end

    local live = source
            and vim.api.nvim_buf_is_valid(source)
            and vim.api.nvim_buf_is_loaded(source)
            and entry.line_start
            and vim.api.nvim_buf_get_lines(source, entry.line_start - 1, entry.line_end, false)
        or nil
    local body = live or vim.split(rec.text, "\n")
    for i = 1, math.min(#body, SNIPPET_LINES) do
        lines[#lines + 1] = { { clipped(body[i]), highlight.CONTEXT } }
    end
    if live and entry.status == "drifted" then
        lines[#lines + 1] = {
            { "was: ", highlight.GROUPS.drifted },
            { clipped(vim.split(rec.text, "\n")[1]), highlight.CONTEXT },
        }
    end
    return lines
end

---Paint the header above the prose and pin the location into the winbar.
---
---The virtual lines sit above row 0, which a window opened at the very top
---does not show until filler rows are asked for; `topfill` is that ask. The
---winbar duplicates the location because virtual lines scroll away with
---line 1 in a note longer than its window.
---@param bufnr integer prose buffer
---@param winid integer editor window
---@param entry sidenote.editor.Note
local function decorate(bufnr, winid, entry)
    local lines = M.header(entry, entry.source)
    vim.api.nvim_buf_clear_namespace(bufnr, M.NAMESPACE, 0, -1)
    vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, 0, 0, {
        virt_lines = lines,
        virt_lines_above = true,
    })

    local label = location.format(entry.record):gsub("%%", "%%%%")
    vim.api.nvim_set_option_value(
        "winbar",
        "%#" .. highlight.CONTEXT .. "#" .. label,
        { win = winid, scope = "local" }
    )
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
