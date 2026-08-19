describe("environment", function()
    it("runs on the Lua 5.1 API", function()
        assert.eq(_VERSION, "Lua 5.1")
    end)

    it("has vim.fn.sha256", function()
        assert.eq(
            vim.fn.sha256("hello"),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    end)

    it("has vim.json", function()
        assert.eq_deep(vim.json.decode(vim.json.encode({ a = 1 })), { a = 1 })
    end)
end)

describe("the runner itself", function()
    it("supports the builtin callable form of assert", function()
        local value = assert(42, "should not raise")
        assert.eq(value, 42)
    end)

    it("reports a failing assertion by throwing", function()
        assert.throws(function()
            assert.eq(1, 2)
        end)
    end)

    it("compares tables structurally, not by identity", function()
        assert.eq_deep({ a = { b = 1 } }, { a = { b = 1 } })
        assert.throws(function()
            assert.eq_deep({ a = 1 }, { a = 1, b = 2 })
        end)
    end)
end)
