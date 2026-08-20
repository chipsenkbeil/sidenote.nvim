---@class sidenote.vimdoc.Opts
---@field project string plugin name, used for the help file tag and every tag prefix
---@field description string one line shown beside the help file tag
---@field version string Neovim version the plugin targets

---@class sidenote.vimdoc.Block
---@field kind "heading"|"paragraph"|"code"|"table" what the block renders as
---@field level integer|nil heading depth, for a heading
---@field text string|nil heading title or paragraph body
---@field tag string|nil explicit tag, overriding the derived one
---@field lang string|nil language of a code block
---@field lines string[]|nil verbatim lines of a code block
---@field rows string[][]|nil cells of a table, header row first

---Markdown to vimdoc, in pure Lua.
---
---Written rather than borrowed so the emitter owns its help tags: a tag is a
---promise to a reader, and deriving every one of them from heading text means
---renaming a heading silently breaks `:help`. A `vimdoc:tag` directive pins the
---ones that matter.
---
---Handles the subset a plugin README actually uses: headings, paragraphs,
---fenced code, tables, and inline code, emphasis and links.
---@class scripts.vimdoc
local M = {}

---Columns a help file is wrapped to.
M.WIDTH = 78

---Spaces prefixing the body of a code block.
M.INDENT = 4

---Longest a derived tag may be.
---
---A tag wider than the page cannot be shown beside anything, and one nobody can
---type is no better than none. Pin a short one with `vimdoc:tag` when a heading
---is genuinely long.
M.MAX_TAG = 40

---@param text string
---@param project string
---@return string
local function derive_tag(text, project)
    local slug = text:lower():gsub("[^%w%s-]", ""):gsub("%s+", "-")
    local tag = ("%s-%s"):format(project, slug)
    if #tag > M.MAX_TAG then
        tag = tag:sub(1, M.MAX_TAG):gsub("-+$", "")
    end
    return tag
end

---Render markdown's inline syntax down to what a help file can show.
---
---Bold and emphasis are dropped because vimdoc has neither; inline code keeps
---its backticks, which the help syntax highlights natively.
---@param text string
---@return string
local function inline(text)
    -- Help references first, before the backticks they sit inside are seen
    text = text:gsub("`:h[elp]*%s+([^`]+)`", "|%1|")
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

---A heading: title on the left, tag right-aligned to the full width.
---
---When the two cannot share a line the tag goes above on its own, which is what
---help files do and what keeps every line inside the page.
---@param left string
---@param tag string
---@return string[]
local function heading(left, tag)
    local marked = ("*%s*"):format(tag)
    local gap = M.WIDTH - #left - #marked
    if gap >= 1 then
        return { left .. (" "):rep(gap) .. marked }
    end

    local out = { (" "):rep(math.max(0, M.WIDTH - #marked)) .. marked }
    vim.list_extend(out, wrap(left, M.WIDTH))
    return out
end

---Split markdown into blocks, resolving directives as it goes.
---@param lines string[]
---@return sidenote.vimdoc.Block[]
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
            if tag then
                pending_tag = tag
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
                            cells[#cells + 1] = inline(cell:match("^%s*(.-)%s*$"))
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

---Column widths that fit the page, shrinking the widest column until they do.
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
        local sum = 2 * (#widths - 1)
        for _, w in ipairs(widths) do
            sum = sum + w
        end
        return sum
    end

    while total() > M.WIDTH do
        local widest = 1
        for i, w in ipairs(widths) do
            if w > widths[widest] then
                widest = i
            end
        end
        if widths[widest] <= 8 then
            break
        end
        widths[widest] = widths[widest] - 1
    end
    return widths
end

---@param rows string[][]
---@return string[]
local function render_table(rows)
    local widths = column_widths(rows)
    local out = {}
    for _, row in ipairs(rows) do
        -- Each cell wraps within its own column, so a long value pushes its row
        -- taller instead of pushing the table past the page
        local wrapped, height = {}, 1
        for i, cell in ipairs(row) do
            wrapped[i] = wrap(cell, widths[i])
            height = math.max(height, #wrapped[i])
        end
        for line = 1, height do
            local parts = {}
            for i = 1, #row do
                local piece = wrapped[i][line] or ""
                parts[#parts + 1] = i == #row and piece or piece .. (" "):rep(widths[i] - #piece)
            end
            out[#out + 1] = (table.concat(parts, "  "):gsub("%s+$", ""))
        end
    end
    return out
end

---@param blocks sidenote.vimdoc.Block[]
---@param opts sidenote.vimdoc.Opts
---@return string[]
local function contents(blocks, opts)
    local out = { ("="):rep(M.WIDTH) }
    vim.list_extend(out, heading("Table of Contents", opts.project .. "-contents"))
    out[#out + 1] = ""

    local index = 0
    for _, block in ipairs(blocks) do
        if block.kind == "heading" and block.level == 2 then
            index = index + 1
            local tag = block.tag or derive_tag(block.text, opts.project)
            local link = ("|%s|"):format(tag)
            local left = ("  %d. %s"):format(index, block.text)
            -- The link is the useful half, so an overlong title is what gives.
            -- ASCII dots, since the budget here is bytes
            local room = M.WIDTH - #link - 1
            if #left > room then
                left = left:sub(1, room - 3) .. "..."
            end
            out[#out + 1] = left .. (" "):rep(M.WIDTH - #left - #link) .. link
        end
    end
    out[#out + 1] = ""
    return out
end

---Render markdown lines as a complete help file.
---@param lines string[]
---@param opts sidenote.vimdoc.Opts
---@return string[]
function M.render(lines, opts)
    local blocks = parse(lines)

    local title = ("*%s.txt*"):format(opts.project)
    local gap = math.max(1, M.WIDTH - #title - #opts.description)
    local out = { title .. (" "):rep(gap) .. opts.description, "" }
    vim.list_extend(out, contents(blocks, opts))

    local index = 0
    for _, block in ipairs(blocks) do
        -- A level-one heading is the document title, already rendered above
        if block.kind == "heading" and block.level == 2 then
            index = index + 1
            local tag = block.tag or derive_tag(block.text, opts.project)
            out[#out + 1] = ("="):rep(M.WIDTH)
            vim.list_extend(out, heading(("%d. %s"):format(index, block.text), tag))
            out[#out + 1] = ""
        elseif block.kind == "heading" and block.level >= 3 then
            local tag = block.tag or derive_tag(block.text, opts.project)
            vim.list_extend(out, heading(block.text:upper(), tag))
            out[#out + 1] = ""
        elseif block.kind == "paragraph" then
            vim.list_extend(out, wrap(inline(block.text), M.WIDTH))
            out[#out + 1] = ""
        elseif block.kind == "code" then
            out[#out + 1] = ">" .. (block.lang or "")
            for _, code in ipairs(block.lines) do
                out[#out + 1] = code ~= "" and (" "):rep(M.INDENT) .. code or ""
            end
            out[#out + 1] = "<"
            out[#out + 1] = ""
        elseif block.kind == "table" then
            vim.list_extend(out, render_table(block.rows))
            out[#out + 1] = ""
        end
    end

    out[#out + 1] = "vim:tw=78:ts=8:ft=help:norl:"
    return out
end

return M
