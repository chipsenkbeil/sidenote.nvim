local record = require("sidenote.core.record")

---Sidecar-pair persistence.
---
---An annotation is two files: prose the user owns, and metadata the plugin
---owns. Metadata is rewritten freely. Prose is created empty and touched again
---only by `write_prose`, applying an edit the user typed and then confirmed —
---no other path opens it for writing.
---@class sidenote.store
local M = {}

---@param root string
---@param id string
---@return string
function M.meta_path(root, id)
    return ("%s/%s.metadata.json"):format(root, id)
end

---@param root string
---@param id string
---@param filetype string
---@return string
function M.prose_path(root, id, filetype)
    return ("%s/%s.%s"):format(root, id, filetype)
end

---@param root string
---@param id string
---@param filetype string
---@return {meta: string, prose: string}
function M.paths(root, id, filetype)
    return { meta = M.meta_path(root, id), prose = M.prose_path(root, id, filetype) }
end

---Annotation id a metadata filename carries, or nil when it is not one.
---@param name string basename within a store root
---@return string|nil
local function meta_id(name)
    return name:match("^(.+)%.metadata%.json$")
end

---Write `content` atomically.
---
---In-place truncation destroys the old bytes before the new ones land, so an
---interrupted write costs the whole file. A rename replaces it or leaves it.
---@param path string
---@param content string
---@return boolean ok
---@return string|nil err
local function write_file(path, content)
    local dir = vim.fn.fnamemodify(path, ":h")
    vim.fn.mkdir(dir, "p")

    -- Dot-prefixed, so a half-written temp can never scan as a record or prose
    local temp = ("%s/.%s.tmp"):format(dir, vim.fn.fnamemodify(path, ":t"))
    local fh, err = io.open(temp, "w")
    if not fh then
        return false, err
    end
    fh:write(content)
    fh:close()

    local ok, rename_err = vim.uv.fs_rename(temp, path)
    if not ok then
        os.remove(temp)
        return false, rename_err
    end
    return true, nil
end

---@param path string
---@return string|nil
local function read_file(path)
    local fh = io.open(path, "r")
    if not fh then
        return nil
    end
    local content = fh:read("*a")
    fh:close()
    return content
end

---Write a new annotation: metadata plus an empty prose file for the user.
---@param root string
---@param rec sidenote.Annotation
---@param filetype string
---@return boolean ok
---@return string|nil err
function M.create(root, rec, filetype)
    local valid, err = record.validate(rec)
    if not valid then
        return false, err
    end
    local ok, write_err = write_file(M.meta_path(root, rec.id), record.encode(rec))
    if not ok then
        return false, write_err
    end
    return write_file(M.prose_path(root, rec.id, filetype), "")
end

---@class sidenote.store.WriteProseOpts
---@field root string store root the annotation lives in
---@field id string annotation whose prose is being written
---@field filetype string extension the prose file carries
---@field lines string[] prose to write, one line per entry

---Write a note's prose, the one sanctioned path into a user-owned file.
---
---Runs only as the direct application of text the user typed and then
---confirmed — never on capture, never on write-back, never on repair.
---@param opts sidenote.store.WriteProseOpts
---@return boolean ok
---@return string|nil err
function M.write_prose(opts)
    local path = M.prose_target(opts.root, opts.id, opts.filetype)
    return write_file(path, table.concat(opts.lines, "\n") .. "\n")
end

---Persist a changed record.
---
---Touches metadata only; prose on disk is left alone.
---@param root string
---@param rec sidenote.Annotation
---@return boolean ok
---@return string|nil err
function M.update(root, rec)
    local valid, err = record.validate(rec)
    if not valid then
        return false, err
    end
    return write_file(M.meta_path(root, rec.id), record.encode(rec))
end

---@param root string
---@param id string
---@return sidenote.Annotation|nil rec nil when the id is absent or its metadata is corrupt
---@return string|nil err set only when metadata is present and failed to decode
function M.read(root, id)
    local raw = read_file(M.meta_path(root, id))
    if not raw then
        return nil, nil
    end
    return record.decode(raw)
end

---Path of the prose file that actually exists for an annotation.
---
---Reads and edits take whatever extension is on disk rather than trusting the
---configured one: a store written while `filetype` was `org` stays usable once
---that setting changes, and a headless run has no user config to consult.
---@param root string
---@param id string
---@param filetype string extension to prefer
---@return string|nil path nil when the annotation has no prose file
function M.prose_file(root, id, filetype)
    local preferred = M.prose_path(root, id, filetype)
    if vim.uv.fs_stat(preferred) then
        return preferred
    end

    local handle = vim.uv.fs_scandir(root)
    if not handle then
        return nil
    end
    while true do
        local name = vim.uv.fs_scandir_next(handle)
        if not name then
            return nil
        end
        if name:sub(1, #id + 1) == id .. "." and not meta_id(name) then
            return root .. "/" .. name
        end
    end
end

---Path a note's prose is edited at: the file that exists, or the configured
---one when none does.
---
---Every caller that opens or rewrites prose resolves through this, so a
---changed `filetype` can never fork one note across two files.
---@param root string
---@param id string
---@param filetype string extension to prefer
---@return string
function M.prose_target(root, id, filetype)
    return M.prose_file(root, id, filetype) or M.prose_path(root, id, filetype)
end

---@param root string
---@param id string
---@param filetype string
---@return string|nil
function M.prose(root, id, filetype)
    local path = M.prose_file(root, id, filetype)
    return path and read_file(path) or nil
end

---First non-blank line of a note's prose, trimmed, or nil when it has none.
---@param root string
---@param id string
---@param filetype string
---@return string|nil
function M.summary(root, id, filetype)
    local text = M.prose(root, id, filetype)
    if not text then
        return nil
    end
    for line in text:gmatch("[^\n]+") do
        local trimmed = vim.trim(line)
        if trimmed ~= "" then
            return trimmed
        end
    end
    return nil
end

---Every annotation id present in a store root, sorted.
---@param root string
---@return string[]
function M.ids(root)
    local ids = {}
    local handle = vim.uv.fs_scandir(root)
    if not handle then
        return ids
    end
    while true do
        local name = vim.uv.fs_scandir_next(handle)
        if not name then
            break
        end
        local id = meta_id(name)
        if id then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

---@param root string
---@param id string
---@param filetype string
---@return boolean removed
function M.delete(root, id, filetype)
    if not vim.uv.fs_stat(M.meta_path(root, id)) then
        return false
    end
    -- Whichever extension is actually there, so changing `filetype` cannot
    -- strand a prose file with no record beside it
    local prose = M.prose_file(root, id, filetype)
    os.remove(M.meta_path(root, id))
    if prose then
        os.remove(prose)
    end
    return true
end

return M
