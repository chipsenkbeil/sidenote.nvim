local buffer = require("sidenote.buffer")
local config = require("sidenote.config")
local id = require("sidenote.util.id")
local pen = require("sidenote.pen")
local project = require("sidenote.store.project")
local record = require("sidenote.core.record")
local store = require("sidenote.store")
local strategy = require("sidenote.store.strategy")
local vcs = require("sidenote.store.vcs")

---@class sidenote.capture.Result
---@field id string id of the new annotation
---@field root string store root it was written to
---@field paths {meta: string, prose: string} files that now exist

---@class sidenote.capture.Opts
---@field scope "file"|"lines"|"range" what to capture
---@field range? integer[] line_start, col_start, line_end, col_end, lines 1-indexed; required outside file scope
---@field kind? "note"|"todo" defaults to note
---@field config? sidenote.Config resolved config, read from vim.g when omitted

---Turns a buffer selection into a stored annotation.
---@class sidenote.capture
local M = {}

---@param bufnr integer
---@param opts sidenote.capture.Opts
---@return sidenote.capture.Result|nil
---@return string|nil err
function M.run(bufnr, opts)
    local cfg = opts.config
    if not cfg then
        local resolved, cfg_err = config.get()
        if cfg_err then
            return nil, cfg_err
        end
        cfg = resolved
    end

    local target, target_err = buffer.target(bufnr, { scope = opts.scope, range = opts.range })
    if not target then
        return nil, target_err
    end

    local roots, strategy_err = strategy.resolve(target.path, cfg)
    if not roots then
        return nil, strategy_err
    end
    local root = roots[1]

    local project_root = project.root(target.path)
    local kind = opts.kind or "note"
    local rec = record.capture({
        id = id.new(),
        project_key = project.key(project_root or vim.fn.fnamemodify(target.path, ":h")),
        path = project_root and project.relative(project_root, target.path) or target.path,
        scope = target.scope,
        line_start = target.line_start,
        line_end = target.line_end,
        col_start = target.col_start,
        col_end = target.col_end,
        content = target.content,
        kind = kind,
        pen = pen.for_kind(kind, cfg),
        vcs = vcs.probe(target.path),
        now = record.now(),
    })

    local ok, write_err = store.create(root, rec, cfg.filetype)
    if not ok then
        return nil, write_err
    end
    return { id = rec.id, root = root, paths = store.paths(root, rec.id, cfg.filetype) }, nil
end

return M
