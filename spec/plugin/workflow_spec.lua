---The workflow duplicates two lists that live elsewhere, because GitHub
---Actions supports no anchors and stylua takes its directories as arguments.
---These check the copies against their sources rather than trusting a comment.

local WORKFLOW = ".github/workflows/tests.yml"

---@param path string
---@return string
local function read(path)
    local fh = assert(io.open(path, "r"), path .. " is missing")
    local body = fh:read("*a")
    fh:close()
    return body
end

---@param text string
---@return string[]
local function sorted_words(text)
    local out = {}
    for word in text:gmatch("%S+") do
        out[#out + 1] = (word:gsub("/$", ""))
    end
    table.sort(out)
    return out
end

---Directories the Makefile points every check at.
---@return string[]
local function lua_dirs()
    return sorted_words(assert(read("Makefile"):match("LUA_DIRS%s*:=%s*([^\n]+)")))
end

---Iterate the pinned releases in the test matrix, in the order written.
---
---Reads the block between `version:` and the key after it, so the matrix can be
---a YAML block list without this needing to know which form it took.
---@return fun(): string|nil
local function matrix_versions()
    local block = assert(read(WORKFLOW):match("version:%s*\n(.-)\n%s*os:"))
    return block:gmatch("(v%d+%.%d+%.%d+)")
end

describe("the tests workflow", function()
    it("exists where GitHub looks for it", function()
        assert.truthy(vim.uv.fs_stat(WORKFLOW))
    end)

    it("formats exactly the directories the Makefile checks", function()
        -- Targets reach stylua as arguments, so the workflow cannot read
        -- LUA_DIRS itself; drift would silently stop formatting a directory
        local args = assert(read(WORKFLOW):match("args:%s*%-%-check%s+([^\n]+)"))
        assert.eq_deep(sorted_words(args), lua_dirs())
    end)

    it("watches every directory the suite reads from", function()
        -- A path filter that misses one means a change there runs no CI at all.
        -- `doc/` matters because the vimdoc tests read the help file
        local body = read(WORKFLOW)
        for _, dir in ipairs(lua_dirs()) do
            assert.contains(body, ('"%s/**"'):format(dir), "unwatched directory: " .. dir)
        end
        for _, path in ipairs({ '"syntax/**"', '"doc/**"', '"Makefile"', '"stylua.toml"' }) do
            assert.contains(body, path, "unwatched path: " .. path)
        end
    end)

    it("filters push and pull_request on the same paths", function()
        local body = read(WORKFLOW)
        local lists = {}
        for list in body:gmatch("paths:\n(.-)\n%s*%a[%w_]*:") do
            lists[#lists + 1] = table.concat(sorted_words(list), " ")
        end
        assert.eq(#lists, 2, "expected a path filter on both push and pull_request")
        assert.eq(lists[1], lists[2])
    end)

    it("uses no YAML anchors, which GitHub Actions does not support", function()
        -- Which is why the two path lists are written out twice
        assert.falsy(read(WORKFLOW):find("\n%s*[%w_]+:%s*&"))
    end)

    it("pins every version it claims to be green on, and never a range", function()
        -- `stable` would stay green while the floor claim quietly went stale,
        -- which is how the 0.10 claim in the docs survived as long as it did
        local pinned = {}
        for version in matrix_versions() do
            pinned[#pinned + 1] = version
        end
        assert.gt(#pinned, 1, "no pinned versions found, so this test proved nothing")
        assert.contains(table.concat(pinned, " "), "v0.11.0", "the floor is not in the matrix")

        -- Only the matrix is checked; the comment above it names `stable` in
        -- order to say why the matrix does not use it
        local block = assert(read(WORKFLOW):match("version:%s*\n(.-)\n%s*os:"))
        assert.falsy(block:find("stable", 1, true), "a moving target is not a pin")
    end)

    it("leaves no gap between the floor and the newest release it pins", function()
        -- A gap means a version nobody runs, which is a version nobody supports
        local seen = {}
        for version in matrix_versions() do
            local major, minor, patch = version:match("^v(%d+)%.(%d+)%.(%d+)$")
            seen[#seen + 1] = { tonumber(major), tonumber(minor), tonumber(patch) }
        end

        for i = 2, #seen do
            local previous, current = seen[i - 1], seen[i]
            local same_line = previous[1] == current[1] and previous[2] == current[2]
            local next_patch = same_line and current[3] == previous[3] + 1
            local next_line = current[2] == previous[2] + 1 and current[3] == 0
            assert.truthy(
                next_patch or next_line,
                ("gap before v%d.%d.%d"):format(current[1], current[2], current[3])
            )
        end
    end)
end)
