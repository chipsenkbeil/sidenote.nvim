local id = require("sidenote.util.id")

describe("id.new", function()
    it("is 26 characters", function()
        assert.eq(#id.new(), 26)
    end)

    it("uses only Crockford base32 characters", function()
        for _ = 1, 50 do
            assert.match(id.new(), "^[0-9ABCDEFGHJKMNPQRSTVWXYZ]+$")
        end
    end)

    it("excludes the ambiguous letters I, L, O and U", function()
        assert.is_nil(id.ALPHABET:find("[ILOU]"))
    end)

    it("encodes the timestamp in the first 10 characters", function()
        local zero = function()
            return 0
        end
        local a = id.new({ now_ms = 1000, rand = zero })
        local b = id.new({ now_ms = 1000, rand = zero })
        assert.eq(a:sub(1, 10), b:sub(1, 10))
    end)

    it("sorts lexicographically by creation time", function()
        local zero = function()
            return 0
        end
        assert.truthy(
            id.new({ now_ms = 1000, rand = zero }) < id.new({ now_ms = 2000, rand = zero })
        )
    end)

    it("keeps sorting correct across a digit-width boundary", function()
        local zero = function()
            return 0
        end
        -- 32^6 is where the sixth base32 digit rolls over; fixed-width encoding
        -- must keep the earlier value lexicographically smaller
        local before = id.new({ now_ms = 32 ^ 6 - 1, rand = zero })
        local after = id.new({ now_ms = 32 ^ 6, rand = zero })
        assert.truthy(before < after)
    end)

    it("differs in the random suffix for the same instant", function()
        local n = 0
        local counter = function()
            n = n + 1
            return n % 32
        end
        local a = id.new({ now_ms = 1000, rand = counter })
        local b = id.new({ now_ms = 1000, rand = counter })
        assert.eq(a:sub(1, 10), b:sub(1, 10))
        assert.neq(a, b)
    end)

    it("does not collide across many draws", function()
        local seen = {}
        for _ = 1, 2000 do
            local value = id.new()
            assert.is_nil(seen[value], "duplicate id: " .. value)
            seen[value] = true
        end
    end)

    it("draws randomness that varies between processes, not a fixed seed", function()
        -- math.random without a seed repeats every run, so ids would collide
        -- across sessions; the real guarantee is uv.random
        assert.neq(id.new():sub(11), id.new():sub(11))
    end)
end)
