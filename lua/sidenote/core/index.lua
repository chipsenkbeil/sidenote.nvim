---@class sidenote.IndexEntry
---@field against string hash of the file content this was resolved against
---@field resolution sidenote.Resolution cached outcome for that content

---@class sidenote.Index
---@field version integer cache format version, discarded when it does not match
---@field entries table<string, sidenote.IndexEntry> mapping of annotation id -> cached resolution
---@field by_path table<string, string[]> mapping of source path -> annotation ids

---Disposable resolution cache.
---
---Everything here is recomputable by globbing the store's `*.metadata.json`
---files, so a corrupt or version-mismatched cache is discarded rather than
---repaired. Anchor status is never authoritative on disk; this is the only
---place it is stored at all.
---@class sidenote.core.index
local M = {}

M.VERSION = 1

---@return sidenote.Index
function M.new()
    return { version = M.VERSION, entries = {}, by_path = {} }
end

---@param path string
---@return sidenote.Index
function M.load(path)
    local fh = io.open(path, "r")
    if not fh then
        return M.new()
    end
    local raw = fh:read("*a")
    fh:close()

    local ok, decoded = pcall(vim.json.decode, raw)
    if not ok or type(decoded) ~= "table" then
        return M.new()
    end
    if decoded.version ~= M.VERSION or type(decoded.entries) ~= "table" then
        return M.new()
    end
    -- An index written before by_path existed is still usable; heal it rather
    -- than discarding resolution results that remain valid
    if type(decoded.by_path) ~= "table" then
        decoded.by_path = {}
    end
    return decoded
end

---@param path string
---@param idx sidenote.Index
---@return boolean ok
---@return string|nil err
function M.save(path, idx)
    local fh, err = io.open(path, "w")
    if not fh then
        return false, err
    end
    fh:write(vim.json.encode(idx))
    fh:close()
    return true, nil
end

---@param idx sidenote.Index
---@param id string
---@param entry sidenote.IndexEntry
function M.put(idx, id, entry)
    idx.entries[id] = entry
end

---@param idx sidenote.Index
---@param id string
---@param file_sha string
---@return sidenote.Resolution|nil
function M.get(idx, id, file_sha)
    local entry = idx.entries[id]
    if not entry or entry.against ~= file_sha then
        return nil
    end
    return entry.resolution
end

---Record that an annotation targets a source file. Idempotent.
---@param idx sidenote.Index
---@param source_path string
---@param id string
function M.track(idx, source_path, id)
    local ids = idx.by_path[source_path]
    if not ids then
        idx.by_path[source_path] = { id }
        return
    end
    for _, existing in ipairs(ids) do
        if existing == id then
            return
        end
    end
    ids[#ids + 1] = id
end

---@param idx sidenote.Index
---@param source_path string
---@param id string
function M.untrack(idx, source_path, id)
    local ids = idx.by_path[source_path]
    if not ids then
        return
    end
    for i, existing in ipairs(ids) do
        if existing == id then
            table.remove(ids, i)
            break
        end
    end
    if #ids == 0 then
        idx.by_path[source_path] = nil
    end
end

---@param idx sidenote.Index
---@param source_path string
---@return string[]
function M.ids_for(idx, source_path)
    return idx.by_path[source_path] or {}
end

return M
