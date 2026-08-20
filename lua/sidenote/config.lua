---@class sidenote.IndicatorConfig
---@field style "sign"|"virt_text"|"highlight"|"underline"|"summary"|"none" how an annotation announces itself
---@field highlight "off"|"on"|"always"|"never" range-highlight overlay: a toggleable default, or pinned

---@class sidenote.PreviewConfig
---@field style "float"|"virt_lines"|"split"|"none" where a note is shown when glanced at
---@field max_lines integer most prose lines rendered in a preview

---@class sidenote.EditorConfig
---@field style "split"|"float"|"toggle"|"current"|"tab" where a note opens for writing
---@field position "left"|"right"|"top"|"bottom" side the split takes
---@field size integer columns for a vertical split, rows for a horizontal one

---@class sidenote.template.Context
---@field path string annotated file, relative to the project root
---@field filetype string extension and filetype the note will use
---@field scope "file"|"lines"|"range" what the annotation covers
---@field line_start integer first annotated line, or 0 for file scope
---@field line_end integer last annotated line, inclusive
---@field text string verbatim anchored bytes, or "" for file scope

---@class sidenote.Config
---@field filetype string extension and filetype for prose files
---@field strategy string|string[]|fun(path: string): string|nil store roots, tried in order
---@field global_dir string root of the machine-wide store
---@field project_dir string directory name used for an in-project store
---@field cache_dir string where scans cache resolutions, never inside a store
---@field template? fun(ctx: sidenote.template.Context): string[]|nil seeds a new note's buffer
---@field pens table<string, string> mapping of pen name -> highlight group its ink uses
---@field pen? string pen freshly captured notes pick up, nil for none
---@field indicator sidenote.IndicatorConfig how annotations appear in a source buffer
---@field preview sidenote.PreviewConfig how a note is glanced at
---@field editor sidenote.EditorConfig how a note opens for writing

---User configuration, resolved from `vim.g.sidenote`.
---@class sidenote.config
local M = {}

local INDICATOR_STYLES = {
    sign = true,
    virt_text = true,
    highlight = true,
    underline = true,
    summary = true,
    none = true,
}
local HIGHLIGHT_MODES = { off = true, on = true, always = true, never = true }
local PREVIEW_STYLES = { float = true, virt_lines = true, split = true, none = true }
local EDITOR_STYLES = { split = true, float = true, toggle = true, current = true, tab = true }
local POSITIONS = { left = true, right = true, top = true, bottom = true }
local STRATEGIES = { project = true, global = true }

---@return sidenote.Config
function M.defaults()
    return {
        -- Extension and filetype of prose files
        filetype = "txt",

        -- Stores to use, tried in order; also the read order
        strategy = { "project", "global" },
        global_dir = vim.fn.stdpath("data") .. "/sidenote",
        project_dir = ".sidenote",

        -- Where scans cache resolutions; never inside a store, which may be
        -- committed
        cache_dir = vim.fn.stdpath("cache") .. "/sidenote",

        -- The pen fresh notes pick up; `:Sidenote pen` changes it live
        -- pen = "yellow",

        -- Pens a note can carry, each naming the highlight group its ink
        -- uses; custom entries merge over these
        pens = {
            yellow = "SidenotePenYellow",
            coral = "SidenotePenCoral",
            blue = "SidenotePenBlue",
            green = "SidenotePenGreen",
        },

        -- Style: sign | virt_text | highlight | underline | summary | none.
        -- The overlay: off | on (toggleable defaults) | always | never
        indicator = { style = "sign", highlight = "on" },

        -- Where a note appears when glanced at:
        -- float | virt_lines | split | none
        preview = { style = "float", max_lines = 20 },

        -- Where a note opens for writing:
        -- split | float | toggle | current | tab
        editor = { style = "split", position = "right", size = 60 },
    }
end

---@param cfg sidenote.Config
---@return string|nil err
local function validate(cfg)
    local function fail(path, detail)
        return ("vim.g.sidenote.%s: %s"):format(path, detail)
    end

    if type(cfg.filetype) ~= "string" then
        return fail("filetype", ("expected a string, got %s"):format(type(cfg.filetype)))
    end
    if type(cfg.global_dir) ~= "string" then
        return fail("global_dir", ("expected a string, got %s"):format(type(cfg.global_dir)))
    end
    if type(cfg.project_dir) ~= "string" then
        return fail("project_dir", ("expected a string, got %s"):format(type(cfg.project_dir)))
    end
    if type(cfg.cache_dir) ~= "string" then
        return fail("cache_dir", ("expected a string, got %s"):format(type(cfg.cache_dir)))
    end

    local entries = cfg.strategy
    if type(entries) == "string" or type(entries) == "function" then
        entries = { entries }
    end
    if type(entries) ~= "table" then
        return fail("strategy", "expected a string, a function, or a list of them")
    end
    for i, entry in ipairs(entries) do
        if type(entry) ~= "function" and not STRATEGIES[entry] then
            return fail(
                ("strategy[%d]"):format(i),
                ("expected project|global or a function, got %s"):format(tostring(entry))
            )
        end
    end

    if cfg.template ~= nil and type(cfg.template) ~= "function" then
        return fail("template", ("expected a function, got %s"):format(type(cfg.template)))
    end

    if type(cfg.pens) ~= "table" then
        return fail("pens", ("expected a table, got %s"):format(type(cfg.pens)))
    end
    for name, group in pairs(cfg.pens) do
        -- The same shape the record accepts: anything else could not sit in
        -- a browser column
        if type(name) ~= "string" or not name:match("^%w[%w_-]*$") then
            return fail("pens", ("%s is not a pen name; use a word"):format(tostring(name)))
        end
        if type(group) ~= "string" then
            return fail(
                ("pens.%s"):format(name),
                ("expected a highlight group name, got %s"):format(type(group))
            )
        end
    end
    if cfg.pen ~= nil and not cfg.pens[cfg.pen] then
        return fail("pen", ("%s is not a configured pen"):format(tostring(cfg.pen)))
    end

    -- Checked before their styles are read: indexing a number would throw, and
    -- a validator that throws takes every entry point down with it
    for _, section in ipairs({ "indicator", "preview", "editor" }) do
        if type(cfg[section]) ~= "table" then
            return fail(section, ("expected a table, got %s"):format(type(cfg[section])))
        end
    end

    if not INDICATOR_STYLES[cfg.indicator.style] then
        return fail("indicator.style", ("unknown style %s"):format(tostring(cfg.indicator.style)))
    end
    if not HIGHLIGHT_MODES[cfg.indicator.highlight] then
        return fail(
            "indicator.highlight",
            ("expected off|on|always|never, got %s"):format(tostring(cfg.indicator.highlight))
        )
    end
    if not PREVIEW_STYLES[cfg.preview.style] then
        return fail("preview.style", ("unknown style %s"):format(tostring(cfg.preview.style)))
    end
    if not EDITOR_STYLES[cfg.editor.style] then
        return fail("editor.style", ("unknown style %s"):format(tostring(cfg.editor.style)))
    end
    if not POSITIONS[cfg.editor.position] then
        return fail(
            "editor.position",
            ("unknown position %s"):format(tostring(cfg.editor.position))
        )
    end
    return nil
end

---Merge user input over the defaults and validate the result.
---
---Returns the defaults alongside any error, so a caller can report the problem
---and still run rather than leaving the user with no plugin at all.
---@param raw? sidenote.Config|fun(): sidenote.Config
---@return sidenote.Config
---@return string|nil err
function M.resolve(raw)
    if type(raw) == "function" then
        raw = raw()
    end
    if raw ~= nil and type(raw) ~= "table" then
        return M.defaults(), "vim.g.sidenote: expected a table or a function returning one"
    end

    local merged = vim.tbl_deep_extend("force", M.defaults(), raw or {})
    local err = validate(merged)
    if err then
        return M.defaults(), err
    end
    return merged, nil
end

---@return sidenote.Config
---@return string|nil err
function M.get()
    return M.resolve(vim.g.sidenote)
end

return M
