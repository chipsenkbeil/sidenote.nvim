---Highlight groups and gutter signs, one per anchor status.
---
---Every group links to a standard group, so a colorscheme decides the actual
---colors and the plugin only decides the severity ordering.
---@class sidenote.highlight
local M = {}

---Prose shown as virtual text beneath annotated code.
M.PROSE = "SidenoteProse"

---A note's context header, comment-colored so it reads as margin.
M.CONTEXT = "SidenoteContext"

---A healthy anchor with no prose yet, dimmed into a deletion candidate.
M.BARE = "SidenoteBare"

---A note window's winbar, backed like a statusline so it reads as chrome.
M.WINBAR = "SidenoteWinbar"

---Severity per status, borrowing the diagnostic vocabulary.
---
---An exact anchor is information, a guessed one is a hint, and anything the
---resolver declined to place is a warning or worse.
---@type table<sidenote.Status, string>
local SEVERITY = {
    attached = "Info",
    drifted = "Hint",
    ambiguous = "Warn",
    orphaned = "Warn",
    filegone = "Error",
}

---Status ink, coloring a glyph or a label rather than the text it points at.
---@type table<sidenote.Status, string>
M.GROUPS = {
    attached = "SidenoteAttached",
    drifted = "SidenoteDrifted",
    ambiguous = "SidenoteAmbiguous",
    orphaned = "SidenoteOrphaned",
    filegone = "SidenoteFilegone",
}

---Name one group per status, `prefix` followed by the capitalized status.
---@param prefix string shared start of every name in the family
---@return table<sidenote.Status, string> family mapping of status -> group name
local function family(prefix)
    local groups = {}
    for status in pairs(M.GROUPS) do
        groups[status] = prefix .. status:sub(1, 1):upper() .. status:sub(2)
    end
    return groups
end

---Groups for the `underline` indicator, which marks the annotated text itself
---rather than tinting the whole line.
---@type table<sidenote.Status, string>
M.UNDERLINES = family("SidenoteUnderline")

---Groups for the `highlight` indicator and the range overlay: marker-pen ink
---over the annotated text, so they need a background, not a glyph color.
---@type table<sidenote.Status, string>
M.MARKS = family("SidenoteMark")

---What each marker links to when a colorscheme says nothing.
---
---`Search` is the closest thing to a yellow highlighter most schemes carry;
---the diagnostic virtual-text groups pair a soft background with a severity.
---@type table<sidenote.Status, string>
local MARK_DEFAULTS = {
    attached = "Search",
    drifted = "DiagnosticVirtualTextHint",
    ambiguous = "DiagnosticVirtualTextWarn",
    orphaned = "DiagnosticVirtualTextWarn",
    filegone = "DiagnosticVirtualTextError",
}

---Background washes for the seeded pens, one pair per screen background.
---
---A wash and nothing else: setting a foreground would paint over the code's
---own colors, which is not how a highlighter reads.
---@type table<string, {dark: string, light: string}>
local PEN_WASHES = {
    SidenotePenYellow = { dark = "#5f5320", light = "#ffef9e" },
    SidenotePenCoral = { dark = "#6b3a34", light = "#ffd6cc" },
    SidenotePenBlue = { dark = "#2f4a6e", light = "#cfe2ff" },
    SidenotePenGreen = { dark = "#2f5a3c", light = "#d1f0d7" },
}

---Extmark priority per status, so the worst mark wins a shared line.
---
---The sign column shows one glyph; an orphan hiding behind an attached note's
---mark would go unnoticed exactly when it matters.
---@type table<sidenote.Status, integer>
M.PRIORITIES = {
    attached = 110,
    drifted = 120,
    ambiguous = 130,
    orphaned = 140,
    filegone = 150,
}

---Gutter glyph per status, one distinct mark each.
---
---A listing shows annotations away from their source, where the status is the
---whole point and has to survive a colorless terminal.
---@type table<sidenote.Status, string>
M.SIGNS = {
    attached = "▍",
    drifted = "╎",
    ambiguous = "?",
    orphaned = "!",
    filegone = "✗",
}

---Glyphs a healthy todo signs with: a box, checked once it is not open.
---
---Kind shows only while the anchor is exact, since hurt is louder than kind.
---@type {open: string, done: string}
M.TODO = { open = "☐", done = "☑" }

---Glyphs that mark one spot rather than extending down a span.
---
---A badge repeated down a span reads as that many separate notes, so a span
---shows one badge with `TAIL` on the lines below it.
---@type table<string, boolean>
M.BADGES = {
    [M.SIGNS.ambiguous] = true,
    [M.SIGNS.orphaned] = true,
    [M.SIGNS.filegone] = true,
    [M.TODO.open] = true,
    [M.TODO.done] = true,
}

---What a badge's continuation lines show in the gutter.
M.TAIL = "│"

function M.setup()
    for status, group in pairs(M.GROUPS) do
        local link = "DiagnosticSign" .. SEVERITY[status]
        vim.api.nvim_set_hl(0, group, { link = link, default = true })
    end
    for status, group in pairs(M.UNDERLINES) do
        local link = "DiagnosticUnderline" .. SEVERITY[status]
        vim.api.nvim_set_hl(0, group, { link = link, default = true })
    end
    for status, group in pairs(M.MARKS) do
        vim.api.nvim_set_hl(0, group, { link = MARK_DEFAULTS[status], default = true })
    end
    local shade = vim.o.background == "light" and "light" or "dark"
    for group, wash in pairs(PEN_WASHES) do
        vim.api.nvim_set_hl(0, group, { bg = wash[shade], default = true })
    end
    vim.api.nvim_set_hl(0, M.PROSE, { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, M.CONTEXT, { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, M.BARE, { link = "NonText", default = true })
    vim.api.nvim_set_hl(0, M.WINBAR, { link = "StatusLine", default = true })
end

return M
