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

---@param path string
---@param content string
---@return boolean ok
---@return string|nil err
local function write_file(path, content)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fh, err = io.open(path, "w")
    if not fh then
        return false, err
    end
    fh:write(content)
    fh:close()
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

---@param root string
---@param id string
---@param filetype string
---@return string|nil
function M.prose(root, id, filetype)
    return read_file(M.prose_path(root, id, filetype))
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
    os.remove(M.meta_path(root, id))
    os.remove(M.prose_path(root, id, filetype))
    return true
end

return M
