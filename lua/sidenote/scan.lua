local buffer = require("sidenote.buffer")
local hash = require("sidenote.core.hash")
local index = require("sidenote.core.index")
local project = require("sidenote.store.project")
local record = require("sidenote.core.record")
local resolve = require("sidenote.core.resolve")
local session = require("sidenote.session")
local store = require("sidenote.store")
local strategy = require("sidenote.store.strategy")

---@class sidenote.scan.Opts
---@field path string a file inside the project, or the project root itself
---@field config sidenote.Config resolved configuration

---Resolves every annotation in a project against the files it points into.
---
---The counterpart to `session`, which resolves one buffer. Nothing here needs
---a buffer to exist, so it works in a headless run — but where one is loaded
---its text wins, so an interactive caller sees unsaved edits.
---@class sidenote.scan
local M = {}

---@param path string absolute path of a source file
---@return string|nil content nil when the file no longer exists
local function content_of(path)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name ~= "" and (vim.uv.fs_realpath(name) or name) == path then
                return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
            end
        end
    end
    return buffer.read(path)
end

---Every record in the project's stores, with the root it came from.
---
---Earlier roots win on an id conflict, matching the read precedence a strategy
---list already has.
---@param roots string[]
---@return {root: string, record: sidenote.Annotation}[]
local function records(roots)
    local found, seen = {}, {}
    for _, root in ipairs(roots) do
        for _, id in ipairs(store.ids(root)) do
            if not seen[id] then
                local rec = store.read(root, id)
                if rec and rec.path then
                    seen[id] = true
                    found[#found + 1] = { root = root, record = rec }
                end
            end
        end
    end
    return found
end

---Cache file a store's resolutions live in, or nil when caching is off.
---
---Under `cache_dir`, never inside the store: the cache is the one replaceable
---artifact, and writing it into a committed store would turn every scan into
---a diff. A config with no `cache_dir` scans uncached.
---@param store_root string
---@param cfg sidenote.Config
---@return string|nil
function M.cache_path(store_root, cfg)
    if type(cfg.cache_dir) ~= "string" or cfg.cache_dir == "" then
        return nil
    end
    local trimmed = (store_root:gsub("/+$", ""))
    local owner = vim.fn.fnamemodify(trimmed, ":h:t")
    return ("%s/%s-%s.json"):format(cfg.cache_dir, owner, hash.sha256(trimmed):sub(1, 12))
end

---Resolve every annotation the project holds.
---
---Sorted by path and then by line, so two runs over unchanged input produce
---the same order and a diff between them means something. Resolutions are
---cached per store, keyed by the file content and the record together, so a
---rewrite of either simply misses and re-resolves.
---@param opts sidenote.scan.Opts
---@return sidenote.session.Entry[]
function M.project(opts)
    local roots = strategy.resolve(opts.path, opts.config)
    if not roots then
        return {}
    end

    local root = project.root(opts.path)

    ---@type table<string, {idx: sidenote.Index, path: string, dirty: boolean}|false>
    local caches = {}
    local function cache_for(store_root)
        if caches[store_root] == nil then
            local path = M.cache_path(store_root, opts.config)
            caches[store_root] = path and { idx = index.load(path), path = path, dirty = false }
                or false
        end
        return caches[store_root] or nil
    end

    local sources = {}
    local entries = {}
    for _, held in ipairs(records(roots)) do
        local rec = held.record
        -- Each source file is read once however many notes target it
        if sources[rec.path] == nil then
            local absolute = root and (root .. "/" .. rec.path) or rec.path
            sources[rec.path] = { content = content_of(absolute) }
        end
        local source = sources[rec.path]

        -- A missing file resolves trivially, so only real content is cached
        local cache = source.content ~= nil and cache_for(held.root) or nil
        local key
        local resolution
        if cache then
            source.sha = source.sha or hash.sha256(source.content)
            key = source.sha .. ":" .. hash.sha256(record.encode(rec))
            resolution = index.get(cache.idx, rec.id, key)
        end
        if not resolution then
            resolution = resolve.resolve(rec, source.content)
            if cache then
                index.put(cache.idx, rec.id, { against = key, resolution = resolution })
                cache.dirty = true
            end
        end
        entries[#entries + 1] = session.entry(held.root, rec, resolution)
    end

    for _, cache in pairs(caches) do
        if cache and cache.dirty then
            vim.fn.mkdir(vim.fn.fnamemodify(cache.path, ":h"), "p")
            index.save(cache.path, cache.idx)
        end
    end

    table.sort(entries, function(a, b)
        if a.record.path ~= b.record.path then
            return a.record.path < b.record.path
        end
        return (a.line_start or math.huge) < (b.line_start or math.huge)
    end)
    return entries
end

return M
