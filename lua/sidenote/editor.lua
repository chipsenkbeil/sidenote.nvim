local config = require("sidenote.config")
local highlight = require("sidenote.highlight")
local location = require("sidenote.location")
local render = require("sidenote.render")
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

---Notes decorated per prose buffer, which is what live refresh re-draws.
---@type table<integer, sidenote.editor.Note>
local decorated = {}

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

---A note's identity as chunks: location, kind, state, swatch and status.
---
---A nil group means "the surface's own base color" — the winbar maps it to
---its background, a preview to the context group — while the swatch keeps
---the note's actual ink (the pen's wash, the status mark for a penless
---note, a squiggle when the style is `underline`) and a short-of-exact
---status keeps its status color, with confidence when it is graded.
---@param entry sidenote.editor.Note
---@return {[1]: string, [2]: string|nil}[] chunks
function M.identity(entry)
    local rec = assert(entry.record)
    local cfg = entry.config or config.get()

    local chunks = {
        { location.format(rec) },
        { "  " .. rec.kind .. " · " .. rec.state .. " · " },
    }
    if rec.pen then
        chunks[#chunks + 1] = { rec.pen .. " " }
    end
    local status = entry.status or "attached"
    if cfg.indicator.style == "underline" then
        chunks[#chunks + 1] = { "~~~", highlight.UNDERLINES[status] }
    else
        local ink = rec.pen and (cfg.pens or {})[rec.pen] or highlight.MARKS[status]
        chunks[#chunks + 1] = { "■", ink }
    end

    if status ~= "attached" then
        local label = status
        local confidence = entry.resolution and entry.resolution.confidence
        if confidence and confidence > 0 and confidence < 1 then
            label = ("%s %.2f"):format(label, confidence)
        end
        chunks[#chunks + 1] = { " · " }
        chunks[#chunks + 1] = { label, highlight.GROUPS[status] }
    end
    return chunks
end

---The winbar line naming the open note: its identity, pinned.
---@param entry sidenote.editor.Note
---@return string winbar statusline-format text
function M.headline(entry)
    local bar = "%#" .. highlight.WINBAR .. "#"
    local parts = { bar, " " }
    for _, chunk in ipairs(M.identity(entry)) do
        local text = chunk[1]:gsub("%%", "%%%%")
        if chunk[2] then
            parts[#parts + 1] = "%#" .. chunk[2] .. "#" .. text .. bar
        else
            parts[#parts + 1] = text
        end
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

---Watch what the header depends on, re-drawing when either side changes.
---@param bufnr integer prose buffer
---@param entry sidenote.editor.Note
local function watch(bufnr, entry)
    local group = vim.api.nvim_create_augroup("sidenote.header." .. bufnr, { clear = true })
    if entry.source and vim.api.nvim_buf_is_valid(entry.source) then
        vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
            group = group,
            buffer = entry.source,
            desc = "Keep the open note's header true to the code it quotes",
            callback = function()
                M.redecorate(bufnr)
            end,
        })
    end
    vim.api.nvim_create_autocmd("BufWinEnter", {
        group = group,
        buffer = bufnr,
        desc = "Re-draw the header on returning to the note",
        callback = function()
            M.redecorate(bufnr)
        end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        buffer = bufnr,
        once = true,
        desc = "Drop the header's state along with its buffer",
        callback = function()
            decorated[bufnr] = nil
            pcall(vim.api.nvim_del_augroup_by_id, group)
        end,
    })
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

    -- The winbar needs a row of its own the first time it lands on a float
    -- sized to its content
    local shape = vim.api.nvim_win_get_config(winid)
    if shape.relative ~= "" and vim.wo[winid].winbar == "" then
        vim.api.nvim_win_set_config(winid, { height = shape.height + 1 })
    end
    vim.api.nvim_set_option_value("winbar", M.headline(entry), { win = winid, scope = "local" })
    -- Reveal the header only while the view sits at the top; a re-draw must
    -- never scroll a note the user has moved down into
    vim.api.nvim_win_call(winid, function()
        if vim.fn.winsaveview().topline == 1 then
            vim.fn.winrestview({ topline = 1, topfill = #lines })
        end
    end)
    decorated[bufnr] = entry
    watch(bufnr, entry)
end

---Re-draw a prose buffer's header from the note's current truth.
---
---The extent comes from the live mark when the source is painted, and the
---record is re-read, so an edit beside the code or a cycle in the browser
---shows through without reopening the note.
---@param bufnr integer prose buffer
---@return boolean drawn
function M.redecorate(bufnr)
    local note = decorated[bufnr]
    if not note or not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end

    local rec = store.read(note.root, note.id)
    if rec then
        note.record = rec
    end
    local live = note.source
        and vim.api.nvim_buf_is_valid(note.source)
        and render.extent(note.source, note.id)
    if live and not live.invalid then
        note.line_start, note.line_end = live.line_start, live.line_end
        note.status = live.status
    end

    local winid = vim.fn.win_findbuf(bufnr)[1]
    if not winid then
        return false
    end
    decorate(bufnr, winid, note)
    return true
end

---Re-draw the header of whichever open note holds `id`, if any.
---@param id string
---@return boolean drawn
function M.redecorate_note(id)
    for bufnr, note in pairs(decorated) do
        if note.id == id then
            return M.redecorate(bufnr)
        end
    end
    return false
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
    -- What DWIM commands and live refresh read back
    vim.b[bufnr].sidenote = { id = entry.id, root = entry.root, source = entry.source }

    local winid = M.winid()
    if winid then
        -- The note being left is flushed first, so the store on disk never
        -- lies to a reader outside the editor
        local leaving = vim.api.nvim_win_get_buf(winid)
        if leaving ~= bufnr and vim.bo[leaving].modified and vim.b[leaving].sidenote then
            vim.api.nvim_buf_call(leaving, function()
                vim.cmd("silent update")
            end)
        end
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
