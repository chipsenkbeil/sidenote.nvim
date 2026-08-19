---Highlight groups and gutter signs, one per anchor status.
---
---Every group links to a standard group, so a colorscheme decides the actual
---colors and the plugin only decides the severity ordering.
---@class sidenote.highlight
local M = {}

---Prose shown as virtual text beneath annotated code.
M.PROSE = "SidenoteProse"

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
    vim.api.nvim_set_hl(0, M.PROSE, { link = "Comment", default = true })
end

return M
