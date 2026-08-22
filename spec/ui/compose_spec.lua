local editor = require("sidenote.editor")
local fixture = require("spec.fixture")
local sidenote = require("sidenote")
local window = require("sidenote.window")

---@param template? fun(ctx: sidenote.template.Context): string[]|nil
---@return sidenote.Config
local function opts(template)
    return {
        filetype = "org",
        strategy = { "project" },
        project_dir = ".sidenote",
        global_dir = vim.fn.tempname(),
        template = template,
        indicator = { style = "sign" },
        preview = { style = "float", max_lines = 20 },
        editor = { style = "split", position = "right", size = 40 },
    }
end

local SOURCE = fixture.SOURCE

---Build a project with its source file current, ready to annotate.
---@return integer bufnr
local function editing()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.sidenote", "p")
    local path = root .. "/m.lua"
    local fh = assert(io.open(path, "w"))
    fh:write(table.concat(SOURCE, "\n") .. "\n")
    fh:close()

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, SOURCE)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
end

---@param cfg sidenote.Config
---@return sidenote.capture.Result
local function added(cfg)
    return assert(sidenote.add({ scope = "lines", range = { 4, 0, 4, 0 }, config = cfg }))
end

---Close the tracked note window, splitting first when it is the last one.
---
---Left open, a later spec's `editor.open` would reuse it instead of
---splitting, and every window assertion there changes meaning.
local function put_away()
    local winid = editor.winid()
    if not winid then
        return
    end
    if #vim.api.nvim_tabpage_list_wins(0) == 1 then
        vim.cmd.split()
    end
    window.close(winid)
end

describe("sidenote.add composing", function()
    after_each(function()
        put_away()
        vim.cmd("silent! %bwipeout!")
    end)

    it("opens the new note for writing, focused", function()
        editing()
        local result = added(opts())
        local winid = assert.not_nil(editor.winid())
        assert.eq(vim.api.nvim_get_current_win(), winid)
        assert.eq(
            vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(winid)),
            (vim.uv.fs_realpath(result.paths.prose))
        )
    end)

    it("seeds the buffer from the template, and the file not at all", function()
        -- The seed is an unsaved edit the user may keep or discard
        editing()
        local result = added(opts(function(ctx)
            return { "* TODO " .. ctx.path, "" }
        end))

        local bufnr = vim.api.nvim_win_get_buf(assert.not_nil(editor.winid()))
        assert.eq_deep(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "* TODO m.lua", "" })
        assert.truthy(vim.bo[bufnr].modified)

        local fh = assert(io.open(result.paths.prose, "r"))
        local on_disk = fh:read("*a")
        fh:close()
        assert.eq(on_disk, "", "the template must never touch the file itself")
    end)

    it("reveals highlights a toggle had hidden, so the capture shows", function()
        local bufnr = editing()
        local cfg = opts()
        cfg.indicator = { style = "sign", highlight = "on" }
        local render = require("sidenote.render")
        render.toggle(bufnr, "on")
        assert.falsy(render.highlighted(bufnr, "on"))

        added(cfg)
        assert.truthy(render.highlighted(bufnr, "on"))
    end)

    it("respects a config that keeps highlights off", function()
        -- Off by configuration is a preference; off by toggle is a moment
        local bufnr = editing()
        local cfg = opts()
        cfg.indicator = { style = "sign", highlight = "off" }
        added(cfg)
        assert.falsy(require("sidenote.render").highlighted(bufnr, "off"))
    end)

    it("hands the template the annotation's own shape", function()
        editing()
        local seen
        added(opts(function(ctx)
            seen = ctx
            return nil
        end))
        assert.eq(seen.path, "m.lua")
        assert.eq(seen.scope, "lines")
        assert.eq(seen.line_start, 4)
        assert.eq(seen.line_end, 4)
        assert.eq(seen.text, "  return 1")
        assert.eq(seen.filetype, "org")
    end)

    it("leaves the buffer empty when no template is configured", function()
        editing()
        added(opts())
        local bufnr = vim.api.nvim_win_get_buf(assert.not_nil(editor.winid()))
        assert.eq_deep(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "" })
        assert.falsy(vim.bo[bufnr].modified)
    end)

    it("captures and opens even when the template throws", function()
        editing()
        local messages = {}
        local original = vim.notify
        vim.notify = function(msg)
            messages[#messages + 1] = tostring(msg)
        end
        local result = added(opts(function()
            error("template boom")
        end))
        vim.notify = original

        assert.not_nil(result.id)
        assert.not_nil(editor.winid())
        assert.contains(table.concat(messages, "\n"), "template")
    end)
end)

describe("sidenote.at_cursor", function()
    before_each(function()
        vim.g.sidenote = { strategy = "project", filetype = "org" }
    end)

    after_each(function()
        vim.g.sidenote = nil
        put_away()
        vim.cmd("silent! %bwipeout!")
    end)

    it("prefers the narrowest note containing the cursor", function()
        -- Overlapping notes are legal
        editing()
        added(opts())
        put_away()
        assert(sidenote.add({ scope = "lines", range = { 3, 0, 5, 0 }, config = opts() }))
        put_away()

        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        local entry = assert.not_nil(sidenote.at_cursor())
        assert.eq(entry.record.line_start, 4)
        assert.eq(entry.record.line_end, 4)
    end)

    it("selects from a caller-held list without resolving again", function()
        -- The caller pays for resolution once per buffer state, not once per cursor move
        editing()
        added(opts())
        put_away()

        local entries = sidenote.entries()
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        assert.eq(assert.not_nil(sidenote.at_cursor(entries)).id, entries[1].id)
    end)

    it("falls back to the file-wide note when nothing narrower contains it", function()
        editing()
        assert(sidenote.add({ scope = "file", config = opts() }))
        put_away()
        assert(sidenote.add({ scope = "lines", range = { 3, 0, 3, 0 }, config = opts() }))
        put_away()

        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        local entry = assert.not_nil(sidenote.at_cursor())
        assert.eq(entry.record.scope, "file")
    end)
end)

describe("config.template validation", function()
    it("rejects a template that is not a function", function()
        local _, err = require("sidenote.config").resolve({ template = "* TODO" })
        assert.contains(err, "template")
    end)
end)
