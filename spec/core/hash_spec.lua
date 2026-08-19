local hash = require("sidenote.core.hash")

describe("hash.sha256", function()
    it("returns lowercase hex", function()
        assert.eq(
            hash.sha256("hello"),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    end)
end)

describe("hash.normalize", function()
    it("collapses whitespace runs within a line", function()
        assert.eq(hash.normalize("local    x   =  1"), "local x = 1")
    end)

    it("trims leading and trailing whitespace per line", function()
        assert.eq(hash.normalize("   a  \n\tb\t"), "a\nb")
    end)

    it("makes reindented code compare equal", function()
        assert.eq(
            hash.normalize("    if x then\n        return 1\n    end"),
            hash.normalize("if x then\n  return 1\nend")
        )
    end)

    it("does not merge separate lines", function()
        assert.neq(hash.normalize("a\nb"), hash.normalize("a b"))
    end)
end)

describe("hash.split", function()
    it("splits on newlines", function()
        assert.eq_deep(hash.split("a\nb\nc"), { "a", "b", "c" })
    end)

    it("does not produce a trailing empty line for a final newline", function()
        assert.eq_deep(hash.split("a\nb\n"), { "a", "b" })
    end)

    it("preserves interior blank lines", function()
        assert.eq_deep(hash.split("a\n\nb"), { "a", "", "b" })
    end)

    it("returns a single empty line for an empty string", function()
        assert.eq_deep(hash.split(""), { "" })
    end)
end)

describe("hash.slice", function()
    local lines = { "one", "two", "three", "four" }

    it("is 1-based and inclusive", function()
        assert.eq(hash.slice(lines, 2, 3), "two\nthree")
    end)

    it("clamps out-of-range bounds", function()
        assert.eq(hash.slice(lines, -5, 99), "one\ntwo\nthree\nfour")
    end)

    it("returns empty string when the range is inverted", function()
        assert.eq(hash.slice(lines, 3, 2), "")
    end)
end)
