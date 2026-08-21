---@class scripts.vimdoc.Opts
---@field project string plugin name, used for the help file tag and every tag prefix
---@field description string one line shown beside the help file tag
---@field version string Neovim version the plugin targets

---@class scripts.vimdoc.Block
---@field kind "heading"|"anchor"|"paragraph"|"code"|"table" what the block renders as
---@field level integer|nil heading depth, for a heading
---@field text string|nil heading title, anchor tag, or paragraph body
---@field tag string|nil explicit tag, overriding the derived one
---@field lang string|nil language of a code block
---@field lines string[]|nil verbatim lines of a code block
---@field rows string[][]|nil cells of a table, header row first

---Markdown to vimdoc, in pure Lua.
---
---Handles the subset a plugin README actually uses: headings, paragraphs,
---fenced code, tables, and inline code, emphasis and links. A tag is derived
---from its heading text unless a `vimdoc:tag` directive pins it, so renaming an
---unpinned heading changes what `:help` answers to.
---@class scripts.vimdoc
local M = {}

---Columns a help file is wrapped to.
local WIDTH = 78

---Spaces prefixing the body of a code block.
local INDENT = 4

---Longest a derived tag may be before it is truncated.
local MAX_TAG = 40

---Spaces separating two table columns.
local COLUMN_GAP = "  "

---Narrowest a table column may be squeezed to.
local MIN_COLUMN = 8

---Stands in for the tail of a title too wide for its contents entry.
local ELLIPSIS = "..."

---@param text string
---@param project string
---@return string
local function derive_tag(text, project)
    local slug = text:lower():gsub("[^%w%s-]", ""):gsub("%s+", "-")
    local tag = ("%s-%s"):format(project, slug)
    if #tag > MAX_TAG then
        tag = tag:sub(1, MAX_TAG):gsub("-+$", "")
    end
    return tag
end

---Render markdown's inline syntax down to what a help file can show.
---
---Bold and emphasis are dropped because vimdoc has neither; inline code keeps
---its backticks, which the help syntax highlights natively.
---@param text string
---@param project string
---@return string
local function inline(text, project)
    text = text:gsub("`:h[elp]*%s+([^`]+)`", "|%1|")

    -- A link within the document becomes the tag it points at, not a URL
    text = text:gsub("%[[^%]]+%]%(#([%w-]+)%)", function(anchor)
        return ("|%s-%s|"):format(project, anchor)
    end)
    text = text:gsub("%[([^%]]+)%]%(([^)]+)%)", "%1 <%2>")
    text = text:gsub("%*%*([^*]+)%*%*", "%1")
    text = text:gsub("%f[%*]%*([^*]+)%*%f[^%*]", "%1")
    return text
end

---@param text string
---@param width integer
---@return string[]
local function wrap(text, width)
    local out, line = {}, ""
    for word in text:gmatch("%S+") do
        if line == "" then
            line = word
        elseif #line + 1 + #word <= width then
            line = line .. " " .. word
        else
            out[#out + 1] = line
            line = word
        end
    end
    if line ~= "" then
        out[#out + 1] = line
    end
    return out
end

---Render a tag alone on its line, right-aligned.
---@param tag string
---@return string
local function anchor(tag)
    local marked = ("*%s*"):format(tag)
    return (" "):rep(math.max(0, WIDTH - #marked)) .. marked
end

---Render a heading, title on the left and tag right-aligned to the full width.
---
---When the two cannot share a line the tag goes above on its own, so a long
---title still fits the page.
---@param left string
---@param tag string
---@return string[]
local function heading(left, tag)
    local marked = ("*%s*"):format(tag)
    local gap = WIDTH - #left - #marked
    if gap >= 1 then
        return { left .. (" "):rep(gap) .. marked }
    end

    local out = { anchor(tag) }
    vim.list_extend(out, wrap(left, WIDTH))
    return out
end

---Split markdown into blocks, resolving directives as it goes.
---@param lines string[]
---@return scripts.vimdoc.Block[]
local function parse(lines)
    local blocks = {}
    local paragraph, pending_tag, ignoring = {}, nil, false

    local function flush()
        if #paragraph > 0 then
            blocks[#blocks + 1] = { kind = "paragraph", text = table.concat(paragraph, " ") }
            paragraph = {}
        end
    end

    local n = 1
    while n <= #lines do
        local line = lines[n]

        if line:match("^%s*<!%-%-") then
            flush()
            local tag = line:match("vimdoc:tag%s+(%S+)")
            local named = line:match("vimdoc:anchor%s+(%S+)")
            if tag then
                pending_tag = tag
            elseif named then
                blocks[#blocks + 1] = { kind = "anchor", text = named }
            elseif line:match("vimdoc:ignore%-start") then
                ignoring = true
            elseif line:match("vimdoc:ignore%-end") then
                ignoring = false
            end
        elseif ignoring then
            flush()
        elseif line:match("^```") then
            flush()
            local lang = line:match("^```(%S*)")
            local body = {}
            n = n + 1
            while n <= #lines and not lines[n]:match("^```") do
                body[#body + 1] = lines[n]
                n = n + 1
            end
            blocks[#blocks + 1] = { kind = "code", lang = lang ~= "" and lang or nil, lines = body }
        elseif line:match("^#+%s") then
            flush()
            local hashes, title = line:match("^(#+)%s+(.*)$")
            blocks[#blocks + 1] = {
                kind = "heading",
                level = #hashes,
                text = title,
                tag = pending_tag,
            }
            pending_tag = nil
        elseif line:match("^%s*|") then
            flush()
            local rows = {}
            while n <= #lines and lines[n]:match("^%s*|") do
                -- The dashed rule under a header row carries no content
                if not lines[n]:match("^[%s|:%-]+$") then
                    local cells = {}
                    for cell in lines[n]:gmatch("|([^|]*)") do
                        if cell:match("%S") then
                            cells[#cells + 1] = cell:match("^%s*(.-)%s*$")
                        end
                    end
                    rows[#rows + 1] = cells
                end
                n = n + 1
            end
            n = n - 1
            blocks[#blocks + 1] = { kind = "table", rows = rows }
        elseif line:match("%S") then
            paragraph[#paragraph + 1] = line:match("^%s*(.-)%s*$")
        else
            flush()
        end
        n = n + 1
    end

    flush()
    return blocks
end

---Compute column widths that fit the page, shrinking the widest until they do.
---@param rows string[][]
---@return integer[]
local function column_widths(rows)
    local widths = {}
    for _, row in ipairs(rows) do
        for i, cell in ipairs(row) do
            widths[i] = math.max(widths[i] or 0, #cell)
        end
    end

    local function total()
        local sum = #COLUMN_GAP * (#widths - 1)
        for _, w in ipairs(widths) do
            sum = sum + w
        end
        return sum
    end

    while total() > WIDTH do
        local widest = 1
        for i, w in ipairs(widths) do
            if w > widths[widest] then
                widest = i
            end
        end
        if widths[widest] <= MIN_COLUMN then
            break
        end
        widths[widest] = widths[widest] - 1
    end
    return widths
end

---@param rows string[][]
---@param project string
---@return string[]
local function render_table(rows, project)
    local widths = column_widths(rows)
    local out = {}
    for _, row in ipairs(rows) do
        -- A long cell wraps within its column, growing its row, not the table
        local wrapped, height = {}, 1
        for i, cell in ipairs(row) do
            wrapped[i] = wrap(inline(cell, project), widths[i])
            height = math.max(height, #wrapped[i])
        end
        for line = 1, height do
            local parts = {}
            for i = 1, #row do
                local piece = wrapped[i][line] or ""
                parts[#parts + 1] = i == #row and piece or piece .. (" "):rep(widths[i] - #piece)
            end
            out[#out + 1] = (table.concat(parts, COLUMN_GAP):gsub("%s+$", ""))
        end
    end
    return out
end

---@param blocks scripts.vimdoc.Block[]
---@param opts scripts.vimdoc.Opts
---@return string[]
local function contents(blocks, opts)
    local out = { ("="):rep(WIDTH) }
    vim.list_extend(out, heading("Table of Contents", opts.project .. "-contents"))
    out[#out + 1] = ""

    local index = 0
    for _, block in ipairs(blocks) do
        if block.kind == "heading" and block.level == 2 then
            index = index + 1
            local tag = block.tag or derive_tag(block.text, opts.project)
            local link = ("|%s|"):format(tag)
            local left = ("  %d. %s"):format(index, block.text)
            -- The link is the useful half, so an overlong title is what gives
            local room = WIDTH - #link - 1
            if #left > room then
                left = left:sub(1, room - #ELLIPSIS) .. ELLIPSIS
            end
            out[#out + 1] = left .. (" "):rep(WIDTH - #left - #link) .. link
        end
    end
    out[#out + 1] = ""
    return out
end

---Render markdown lines as a complete help file.
---@param lines string[]
---@param opts scripts.vimdoc.Opts
---@return string[]
function M.render(lines, opts)
    local blocks = parse(lines)

    local title = ("*%s.txt*"):format(opts.project)
    local gap = math.max(1, WIDTH - #title - #opts.description)
    local out = { title .. (" "):rep(gap) .. opts.description, "" }
    vim.list_extend(out, contents(blocks, opts))

    local index = 0
    for _, block in ipairs(blocks) do
        -- A level-one heading is the document title, which the front matter carries
        if block.kind == "heading" and block.level == 2 then
            index = index + 1
            local tag = block.tag or derive_tag(block.text, opts.project)
            out[#out + 1] = ("="):rep(WIDTH)
            vim.list_extend(out, heading(("%d. %s"):format(index, block.text), tag))
            out[#out + 1] = ""
        elseif block.kind == "heading" and block.level >= 3 then
            local tag = block.tag or derive_tag(block.text, opts.project)
            vim.list_extend(out, heading(block.text:upper(), tag))
            out[#out + 1] = ""
        elseif block.kind == "anchor" then
            -- No blank after it: the tag belongs to whatever follows it, not to
            -- the section it sits in
            out[#out + 1] = anchor(block.text)
        elseif block.kind == "paragraph" then
            vim.list_extend(out, wrap(inline(block.text, opts.project), WIDTH))
            out[#out + 1] = ""
        elseif block.kind == "code" then
            out[#out + 1] = ">" .. (block.lang or "")
            for _, code in ipairs(block.lines) do
                out[#out + 1] = code ~= "" and (" "):rep(INDENT) .. code or ""
            end
            out[#out + 1] = "<"
            out[#out + 1] = ""
        elseif block.kind == "table" then
            vim.list_extend(out, render_table(block.rows, opts.project))
            out[#out + 1] = ""
        end
    end

    out[#out + 1] = "vim:tw=78:ts=8:ft=help:norl:"
    return out
end

return M
