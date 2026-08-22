---The world a spec builds on: the configuration, and the source it annotates.
---
---These were copied into every spec that needed them, which is how eighteen
---copies of one configuration came to disagree about what a test's world looks
---like. Gathering them means a required field added to `sidenote.Config` is one
---edit here rather than a hunt, and two specs cannot drift on what a source
---file is.
---
---Only what is genuinely shared belongs here. A fixture built for one spec is
---clearer left in that spec, where a reader can see it.
---@class spec.Fixture
local M = {}

local capture = require("sidenote.capture")
local store = require("sidenote.store")

---Source of the file a spec annotates.
M.SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---Source of a second, different file, for a spec that needs two.
M.SECOND = { "-- beta", "local x = 1", "return x" }

---Build a configuration for a test, `overrides` merged over the defaults.
---
---`global_dir` is a fresh temporary directory on every call, so two configs
---built inside one test do not name the same global store. Callers pin
---`strategy = { "project" }`, which is what keeps that from mattering.
---@param overrides? table<string, any> fields merged over the defaults
---@return sidenote.Config
function M.opts(overrides)
    return vim.tbl_deep_extend("force", {
        filetype = "org",
        strategy = { "project" },
        project_dir = ".sidenote",
        global_dir = vim.fn.tempname(),
        indicator = { style = "sign" },
        preview = { style = "float", max_lines = 20 },
        editor = { style = "split", position = "right", size = 60 },
    }, overrides or {})
end

---Write `files` into a fresh project root, and hand back its resolved path.
---
---Resolved because macOS answers `/var` with `/private/var`: a root compared
---against a path the plugin resolved has to have been resolved the same way.
---@param files table<string, string[]> mapping of file name -> its lines
---@return string root
function M.project(files)
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.sidenote", "p")
    for name, lines in pairs(files) do
        local fh = assert(io.open(root .. "/" .. name, "w"))
        fh:write(table.concat(lines, "\n") .. "\n")
        fh:close()
    end
    return assert(vim.uv.fs_realpath(root))
end

---Build a project holding one annotated file, already open in a buffer.
---@param lines? string[] the file's content, `M.SOURCE` by default
---@return integer bufnr buffer holding the file
---@return string root resolved project root
---@return string path resolved absolute path of the file
function M.project_buffer(lines)
    local body = lines or M.SOURCE
    local root = M.project({ ["m.lua"] = body })
    local path = assert(vim.uv.fs_realpath(root .. "/m.lua"))

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, body)
    return bufnr, root, path
end

---Build a throwaway directory tree, and hand back its root.
---
---A trailing slash makes a directory; anything else makes an empty file.
---@param paths string[] paths relative to the root
---@return string root
function M.tree(paths)
    local root = vim.fn.tempname()
    for _, rel in ipairs(paths) do
        local full = root .. "/" .. rel
        if rel:sub(-1) == "/" then
            vim.fn.mkdir(full, "p")
        else
            vim.fn.mkdir(vim.fn.fnamemodify(full, ":h"), "p")
            local fh = assert(io.open(full, "w"))
            fh:write("")
            fh:close()
        end
    end
    return root
end

---@class spec.fixture.NoteOpts
---@field bufnr? integer buffer to annotate, taking the place of `path`
---@field path? string file to annotate, loaded into a buffer first
---@field line? integer line the note covers, 1-based, the first by default
---@field range? integer[] capture range, taking the place of `line`
---@field scope? "file"|"lines"|"range" what the note covers, lines by default
---@field kind? "note"|"todo" what the note is, a note by default
---@field state? "open"|"resolved"|"wontfix"|"archived" written after capture, left open when absent
---@field prose? string[] prose written to the note's file, none written when absent
---@field detach? boolean drop the buffer once captured, so a scan reads disk instead of it
---@field config? sidenote.Config configuration to capture under, `M.opts()` by default

---Capture a note, and write the prose a test wants it to hold.
---
---The whole result comes back rather than an id, since which part a spec
---needs — the id, the root, the record — is the spec's business.
---@param opts spec.fixture.NoteOpts
---@return sidenote.capture.Result
function M.annotate(opts)
    local cfg = opts.config or M.opts()
    local bufnr, opened = opts.bufnr, false
    if not bufnr then
        bufnr = vim.fn.bufadd(opts.path)
        vim.fn.bufload(bufnr)
        opened = true
    end

    local scope = opts.scope or "lines"
    local line = opts.line or 1
    local result = assert(capture.run(bufnr, {
        scope = scope,
        range = scope ~= "file" and (opts.range or { line, 0, line, 0 }) or nil,
        kind = opts.kind,
        config = cfg,
    }))

    -- Only what this built is torn down; a caller's own buffer is its business
    if opts.detach and opened then
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end

    if opts.prose then
        local fh = assert(io.open(store.prose_path(result.root, result.id, cfg.filetype), "w"))
        fh:write(table.concat(opts.prose, "\n") .. "\n")
        fh:close()
    end

    if opts.state then
        local rec = assert(store.read(result.root, result.id))
        rec.state = opts.state
        store.update(result.root, rec)
    end

    return result
end

return M
