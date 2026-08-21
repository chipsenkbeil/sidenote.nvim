local git = require("harness.git")

---Build a throwaway repo with a known history.
---@return string dir path to the new repository
local function fixture()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local function sh(cmd)
        local out =
            vim.fn.system({ "sh", "-c", ("cd %s && %s"):format(vim.fn.shellescape(dir), cmd) })
        assert(vim.v.shell_error == 0, out)
    end
    sh("git init -q")
    sh("git config user.email t@t && git config user.name t")
    sh("printf 'aaa\\nbbb\\nccc\\nddd\\n' > f.txt")
    sh("git add f.txt && git commit -qm one")
    -- Insert two lines at the top and delete 'ccc'
    sh("printf 'zero\\nhalf\\naaa\\nbbb\\nddd\\n' > f.txt")
    sh("git add f.txt && git commit -qm two")
    return dir
end

describe("git.show", function()
    it("reads a file at an old revision", function()
        assert.eq(git.show(fixture(), "HEAD~1", "f.txt"), "aaa\nbbb\nccc\nddd\n")
    end)

    it("returns nil for a path that did not exist", function()
        assert.is_nil(git.show(fixture(), "HEAD~1", "nope.txt"))
    end)
end)

describe("git.head", function()
    it("returns a full commit id", function()
        local head = git.head(fixture())
        assert.eq(#head, 40)
        assert.match(head, "^%x+$")
    end)
end)

describe("git.alive", function()
    it("maps a surviving line to its new number", function()
        -- 'aaa' was line 1 at HEAD~1 and is line 3 at HEAD
        assert.eq(
            git.alive(fixture(), { base_rev = "HEAD~1", path = "f.txt", ranges = { { 1, 1 } } })[1],
            3
        )
    end)

    it("reports a deleted line as nil", function()
        -- 'ccc' was line 3 at HEAD~1 and was deleted
        assert.is_nil(
            git.alive(fixture(), { base_rev = "HEAD~1", path = "f.txt", ranges = { { 3, 3 } } })[3]
        )
    end)

    it("answers several ranges in one call", function()
        local map = git.alive(
            fixture(),
            { base_rev = "HEAD~1", path = "f.txt", ranges = { { 1, 1 }, { 3, 3 }, { 4, 4 } } }
        )
        assert.eq(map[1], 3)
        assert.is_nil(map[3])
        assert.eq(map[4], 5)
    end)

    it("returns an empty map when the path is unknown", function()
        assert.eq_deep(
            git.alive(fixture(), { base_rev = "HEAD~1", path = "nope.txt", ranges = { { 1, 1 } } }),
            {}
        )
    end)
end)
