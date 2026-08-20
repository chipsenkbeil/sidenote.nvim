---Highlight groups and gutter signs, one per anchor status.
---
---Every group links to a standard group, so a colorscheme decides the actual
---colors and the plugin only decides the severity ordering.
---@class sidenote.highlight
local M = {}

---Prose shown as virtual text beneath annotated code.
M.PROSE = "SidenoteProse"

---The note editor's context header, comment-colored so it reads as margin.
M.CONTEXT = "SidenoteContext"

---A healthy anchor with no prose yet, dimmed into a deletion candidate.
M.BARE = "SidenoteBare"

---Severity ordering, expressed by borrowing the diagnostic vocabulary: an
---exact anchor is information, a guessed one is a hint, and anything the
---resolver declined to place is a warning or worse.
---
---Written once and used for every family of groups below, so the ordering
---cannot drift between them.
---@type table<sidenote.Status, string>
local SEVERITY = {
    attached = "Info",
    drifted = "Hint",
    ambiguous = "Warn",
    orphaned = "Warn",
    filegone = "Error",
}

---@type table<sidenote.Status, string>
M.GROUPS = {
    attached = "SidenoteAttached",
    drifted = "SidenoteDrifted",
    ambiguous = "SidenoteAmbiguous",
    orphaned = "SidenoteOrphaned",
    filegone = "SidenoteFilegone",
}

---Groups for the `underline` indicator, which marks the annotated text itself
---rather than tinting the whole line.
---@type table<sidenote.Status, string>
M.UNDERLINES = {}
for status in pairs(M.GROUPS) do
    M.UNDERLINES[status] = "SidenoteUnderline" .. status:sub(1, 1):upper() .. status:sub(2)
end

---Groups for the `highlight` indicator and the range overlay: marker-pen ink
---over the annotated text, so they need a background, not a glyph color.
---@type table<sidenote.Status, string>
M.MARKS = {}
for status in pairs(M.GROUPS) do
    M.MARKS[status] = "SidenoteMark" .. status:sub(1, 1):upper() .. status:sub(2)
end

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
---Beside visible code the highlight alone would carry the difference, but the
---browser lists annotations away from their source, where the status is the
---whole point and has to survive a colourless terminal.
---@type table<sidenote.Status, string>
M.SIGNS = {
    attached = "▍",
    drifted = "╎",
    ambiguous = "?",
    orphaned = "!",
    filegone = "✗",
}

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
end

return M
