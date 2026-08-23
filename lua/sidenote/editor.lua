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

---Display columns the rule closing a header takes.
local DIVIDER_WIDTH = 48

---Window an open note sits in, reused by the note opened after it.
---@type integer|nil
local current

---Mapping of prose buffer -> the note its header draws.
---@type table<integer, sidenote.editor.Note>
local decorated = {}

---The editor's window, if it is still open.
---@return integer|nil winid nil when no note is open
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
---@field status? sidenote.Status anchor status at the last resolution, attached when absent
---@field line_start? integer first line the note covers now
---@field line_end? integer last line, inclusive
---@field source? integer loaded buffer of the annotated file, for the snippet
---@field config? sidenote.Config pens and ink style, from `vim.g.sidenote` when absent

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

---Cut the middle out of `path`, keeping its head and as much tail as fits.
---
---The filename and the directory holding it are what a reader navigates by,
---so the tail is filled in from the end until `room` runs out.
---@param path string
---@param room integer display columns available
---@return string
local function elided(path, room)
    local parts = vim.split(path, "/", { plain = true })
    local name = parts[#parts]
    if #parts < 3 or vim.fn.strdisplaywidth(name) >= room then
        return name
    end

    local head = parts[1]
    local tail = { name }
    local width = vim.fn.strdisplaywidth(head .. "/…/" .. name)
    for i = #parts - 1, 2, -1 do
        local wider = width + vim.fn.strdisplaywidth(parts[i] .. "/")
        if wider > room then
            break
        end
        table.insert(tail, 1, parts[i])
        width = wider
    end
    return head .. "/…/" .. table.concat(tail, "/")
end

---Name `path` in the shortest form that still fits `room`.
---
---Tried in order, the first that fits winning: as stored, since a
---project-relative path is already the shortest true name for it; relative to
---the working directory, which is what every other window is naming it by;
---and the home directory as `~`. When none of them fit, the middle goes.
---
---Display only. `location.format` is half of the browser's parse/render
---round-trip, and that has to keep producing the stored path.
---@param path string
---@param room integer|nil display columns available, unbounded when absent
---@return string
local function fitted(path, room)
    local tries = { path }
    if path:sub(1, 1) == "/" then
        -- Appended rather than listed: `relpath` answers nil for a path the
        -- working directory does not hold, and a nil ends an ipairs at once
        tries = {}
        local rel = vim.fs.relpath(vim.fn.getcwd(), path)
        if rel then
            tries[#tries + 1] = rel
        end
        tries[#tries + 1] = vim.fn.fnamemodify(path, ":~")
        tries[#tries + 1] = path
    end

    local shortest
    for _, try in ipairs(tries) do
        if not room or vim.fn.strdisplaywidth(try) <= room then
            return try
        end
        if not shortest or #try < #shortest then
            shortest = try
        end
    end
    return elided(shortest or path, room or math.huge)
end

---Where a note points now, shortened to what the header has room for.
---
---The extent, not the record: an edit above the note moves the mark, and the
---snippet already numbers its lines from there. A header naming the stored
---line beside a snippet numbering the live one states two positions at once.
---@param entry sidenote.editor.Note
---@param room integer|nil display columns the location may take
---@return string
local function where(entry, room)
    local rec = assert(entry.record)
    local shown = vim.tbl_extend("force", {}, rec)
    if entry.line_start and rec.scope ~= "file" then
        shown.line_start, shown.line_end = entry.line_start, entry.line_end
    end
    shown.path = fitted(rec.path, room)
    return location.format(shown)
end

---A note's identity as chunks: location, kind, state, swatch and status.
---
---A chunk with no group takes the caller's own base color. The swatch
---carries the note's ink — the pen's wash, the status mark for a penless
---note, a squiggle under the `underline` style — and a short-of-exact
---status keeps its status color, with its confidence when graded.
---
---The location is built last and given whatever `room` the rest left it, so
---the part that can shorten is the part that pays for a narrow window.
---@param entry sidenote.editor.Note
---@param room? integer display columns the whole identity has
---@return {[1]: string, [2]: string|nil}[] chunks
function M.identity(entry, room)
    local rec = assert(entry.record)
    local cfg = entry.config or config.get()

    -- What the location is left with, once everything of fixed width has
    -- taken its share
    local chunks = {
        { "  " .. rec.kind .. " · " .. rec.state .. " · " },
    }
    if rec.pen then
        chunks[#chunks + 1] = { rec.pen .. " " }
    end
    local status = entry.status or "attached"
    if cfg.indicator.style == "underline" then
        chunks[#chunks + 1] = { "~~~", highlight.UNDERLINES[status] }
    else
        local ink = rec.pen and cfg.pens[rec.pen] or highlight.MARKS[status]
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

    local taken = 1
    for _, chunk in ipairs(chunks) do
        taken = taken + vim.fn.strdisplaywidth(chunk[1])
    end
    table.insert(chunks, 1, { where(entry, room and math.max(room - taken, 1) or nil) })
    return chunks
end

---The winbar line naming the open note: its identity, pinned.
---@param entry sidenote.editor.Note
---@param room? integer display columns the bar has, unbounded when absent
---@return string winbar statusline-format text
function M.headline(entry, room)
    local bar = "%#" .. highlight.WINBAR .. "#"
    local parts = { bar, " " }
    for _, chunk in ipairs(M.identity(entry, room)) do
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
    lines[#lines + 1] = { { ("─"):rep(DIVIDER_WIDTH), highlight.CONTEXT } }
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
        -- No gravity: typing from the very top of an empty note must not
        -- drag the header down with the text, leaving prose above it
        vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, 0, 0, {
            virt_lines = lines,
            virt_lines_above = true,
            right_gravity = false,
        })
    end

    -- The winbar needs a row of its own the first time it lands on a float
    -- sized to its content
    local shape = vim.api.nvim_win_get_config(winid)
    if shape.relative ~= "" and vim.wo[winid].winbar == "" then
        vim.api.nvim_win_set_config(winid, { height = shape.height + 1 })
    end
    local room = vim.api.nvim_win_get_width(winid)
    vim.api.nvim_set_option_value(
        "winbar",
        M.headline(entry, room),
        { win = winid, scope = "local" }
    )

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
---record is re-read from the store, so an edit beside the code or a change
---to the note itself shows through without reopening it.
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

---@class sidenote.editor.Opts: sidenote.EditorConfig
---@field focus? boolean take the cursor into the note, leaving it put when absent

---Open a note, returning the window showing it.
---
---The `toggle` style behaves as `split`, except that asking for the note
---already on show puts it away instead and returns nil.
---@param entry sidenote.editor.Note
---@param opts sidenote.editor.Opts
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

    -- What a reader of the prose buffer follows back to the annotation
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
