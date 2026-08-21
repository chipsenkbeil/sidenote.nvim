---The runner cannot test itself in-process, so these drive a nested one.

---Run `body` as a spec in a nested runner process.
---@param body string spec source to run
---@return string output stdout and stderr, interleaved
---@return integer code
local function nested(body)
    local path = vim.fn.tempname() .. "_spec.lua"
    local fh = assert(io.open(path, "w"))
    fh:write(body)
    fh:close()
    local out = vim.fn.system({ "nvim", "-l", "spec/runner.lua", path })
    return out, vim.v.shell_error
end

describe("the runner's hook handling", function()
    it("fails only the affected test when a before_each throws", function()
        -- Unprotected, one hook failure would kill the run and silently skip every later spec
        local out, code = nested([[
            describe("with a broken hook", function()
                before_each(function()
                    error("hook boom")
                end)
                it("cannot run", function() end)
            end)
            describe("unaffected", function()
                it("still runs", function() end)
            end)
        ]])
        assert.neq(code, 0)
        assert.contains(out, "1 passed, 1 failed")
        assert.contains(out, "hook boom")
    end)

    it("exits zero when hooks and tests all pass", function()
        local out, code = nested([[
            describe("healthy", function()
                before_each(function() end)
                it("runs", function() end)
            end)
        ]])
        assert.eq(code, 0)
        assert.contains(out, "1 passed, 0 failed")
    end)
end)
