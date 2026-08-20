local record = require("sidenote.core.record")

---Sidecar-pair persistence.
---
---An annotation is two files: prose the user owns, and metadata the plugin
---owns. Only metadata is ever rewritten. The prose file is created empty once
---and never opened for writing again, which makes the ownership boundary
---physical rather than a rule to remember.
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

---Write `content` through a hidden sibling and a rename.
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
---Every other write in this module touches metadata alone. This exists because
---the browser lets prose be edited in place, and it runs only as the direct
---application of text the user typed and then confirmed — never on capture,
---never on write-back, never on repair.
---@param opts sidenote.store.WriteProseOpts
---@return boolean ok
---@return string|nil err
function M.write_prose(opts)
    local path = M.prose_target(opts.root, opts.id, opts.filetype)
    return write_file(path, table.concat(opts.lines, "\n") .. "\n")
end

---Persist a changed record. Touches metadata only.
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
---@return sidenote.Annotation|nil
---@return string|nil err
function M.read(root, id)
    local raw = read_file(M.meta_path(root, id))
    if not raw then
        return nil, nil
    end
    return record.decode(raw)
end

---Path of the prose file that actually exists for an annotation.
---
---Reads and edits fall back to whatever extension is on disk rather than
---trusting the configured one. A store written while `filetype` was `org` has
---to stay usable after that setting changes, and a headless run has no user
---config to consult at all. Only creating a new note uses the configured
---extension unconditionally.
---@param root string
---@param id string
---@param filetype string extension to prefer
---@return string|nil
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
        if name:sub(1, #id + 1) == id .. "." and not name:match("%.metadata%.json$") then
            return root .. "/" .. name
        end
    end
end

---Path a note's prose is edited at: the file that exists, or the configured
---one when none does.
---
---Every surface that opens or rewrites prose resolves through this, so a
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
        local id = name:match("^(.+)%.metadata%.json$")
        if id then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

---Rebuild the index by reading every record in the given `roots`.
---
---Earlier roots win on an id conflict, matching the read precedence of a
---strategy list.
---@param roots string[]
---@return sidenote.Index
function M.rebuild(roots)
    local index = require("sidenote.core.index")
    local idx = index.new()
    local seen = {}
    for _, root in ipairs(roots) do
        for _, id in ipairs(M.ids(root)) do
            if not seen[id] then
                local rec = M.read(root, id)
                if rec and rec.path then
                    seen[id] = true
                    index.track(idx, rec.path, id)
                end
            end
        end
    end
    return idx
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
