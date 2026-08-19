---Highlight groups and gutter signs, one per anchor status.
---
---Every group links to a standard group, so a colorscheme decides the actual
---colors and the plugin only decides the severity ordering.
---@class sidenote.highlight
local M = {}

---Prose shown as virtual text beneath annotated code.
M.PROSE = "SidenoteProse"

---@type table<sidenote.Status, string>
M.GROUPS = {
    attached = "SidenoteAttached",
    drifted = "SidenoteDrifted",
    ambiguous = "SidenoteAmbiguous",
    orphaned = "SidenoteOrphaned",
    filegone = "SidenoteFilegone",
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

---Severity ordering, expressed by borrowing the diagnostic groups: an exact
---anchor is information, a guessed one is a hint, and anything the resolver
---declined to place is a warning or worse.
---@type table<sidenote.Status, string>
local LINKS = {
    attached = "DiagnosticSignInfo",
    drifted = "DiagnosticSignHint",
    ambiguous = "DiagnosticSignWarn",
    orphaned = "DiagnosticSignWarn",
    filegone = "DiagnosticSignError",
}

function M.setup()
    for status, group in pairs(M.GROUPS) do
        vim.api.nvim_set_hl(0, group, { link = LINKS[status], default = true })
    end
    vim.api.nvim_set_hl(0, M.PROSE, { link = "Comment", default = true })
end

return M
