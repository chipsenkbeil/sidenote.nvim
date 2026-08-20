local health = require("sidenote.health")

---@class spec.plugin.Reported
---@field ok string[] everything reported as working
---@field info string[] everything reported as absent but optional
---@field warn string[] everything reported as a warning
---@field error string[] everything reported as broken

---Run a health check while standing in for `vim.health`, so the report can be
---read rather than only looked at.
---@param fn function
---@return spec.plugin.Reported
local function captured(fn)
    local real = vim.health
    local out = { ok = {}, info = {}, warn = {}, error = {} }

    ---@param level string
    ---@return fun(message: string)
    local function collect(level)
        return function(message)
            out[level][#out[level] + 1] = message
        end
    end

    vim.health = {
        start = function() end,
        ok = collect("ok"),
        info = collect("info"),
        warn = collect("warn"),
        error = collect("error"),
    }
    local ok, err = pcall(fn)
    vim.health = real
    assert(ok, err)
    return out
end

---@param reported string[]
---@param needle string
---@return boolean
local function mentions(reported, needle)
    for _, message in ipairs(reported) do
        if message:find(needle, 1, true) then
            return true
        end
    end
    return false
end

---Run a function with the working directory somewhere else.
---@param dir string
---@param fn function
local function within(dir, fn)
    local before = vim.fn.getcwd()
    vim.fn.chdir(dir)
    local ok, err = pcall(fn)
    vim.fn.chdir(before)
    assert(ok, err)
end

describe("health.check", function()
    it("reports a valid configuration as ok", function()
        local report = captured(health.check)
        assert.truthy(mentions(report.ok, "configuration valid"))
        assert.eq_deep(report.error, {})
    end)

    it("reports a broken configuration as an error, and carries on", function()
        local before = vim.g.sidenote
        vim.g.sidenote = { indicator = { style = "sparkles" } }
        local report = captured(health.check)
        vim.g.sidenote = before

        assert.truthy(mentions(report.error, "indicator.style"))
        assert.gt(#report.ok, 0, "one bad field must not stop the rest of the report")
    end)

    it("reports whether the global store can be written", function()
        assert.truthy(mentions(captured(health.check).ok, "global store writable"))
    end)

    it("reports the version control it found", function()
        -- Optional rather than required, so its absence is info and never a
        -- warning
        local report = captured(health.check)
        assert.truthy(mentions(report.ok, "provenance") or mentions(report.info, "provenance"))
    end)

    it("says nothing about treesitter, which no tier reads", function()
        -- The old line checked the checkhealth buffer's own filetype mapping,
        -- reporting readiness for a tier that was cut
        local report = captured(health.check)
        assert.falsy(mentions(report.ok, "treesitter") or mentions(report.info, "treesitter"))
    end)

    it("never reports a missing optional tool as a warning", function()
        -- The plugin has no required dependencies, so nothing absent is a fault
        assert.eq_deep(captured(health.check).warn, {})
    end)
end)

describe("health.check project store", function()
    it("counts the annotations in a project store it finds", function()
        local root = vim.fn.tempname()
        vim.fn.mkdir(root .. "/.sidenote", "p")
        local fh = assert(io.open(root .. "/.sidenote/01ABC.metadata.json", "w"))
        fh:write("{}")
        fh:close()

        within(root, function()
            assert.truthy(mentions(captured(health.check).ok, "holds 1 annotation"))
        end)
    end)

    it("reports a project with no store yet as information, not a problem", function()
        local root = vim.fn.tempname()
        vim.fn.mkdir(root .. "/.git", "p")

        within(root, function()
            local report = captured(health.check)
            assert.truthy(mentions(report.info, "no store yet"))
            assert.eq_deep(report.error, {})
        end)
    end)

    it("says notes will go to the global store when nothing marks a project", function()
        local loose = vim.fn.tempname()
        vim.fn.mkdir(loose, "p")

        within(loose, function()
            assert.truthy(mentions(captured(health.check).info, "global store"))
        end)
    end)
end)
