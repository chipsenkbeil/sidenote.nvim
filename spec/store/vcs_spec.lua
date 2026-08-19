local vcs = require("sidenote.store.vcs")

---@return string
local function git_repo()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local function sh(cmd)
        local out =
            vim.fn.system({ "sh", "-c", ("cd %s && %s"):format(vim.fn.shellescape(dir), cmd) })
        assert(vim.v.shell_error == 0, out)
    end
    sh("git init -q && git config user.email t@t && git config user.name t")
    sh("printf 'a\\n' > f.txt && git add f.txt && git commit -qm one")
    return dir
end

describe("vcs.probe", function()
    it("returns nil outside any repository", function()
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        assert.is_nil(vcs.probe(dir .. "/f.txt"))
    end)

    it("reports git with a full commit id", function()
        local got = vcs.probe(git_repo() .. "/f.txt")
        assert.eq(got.kind, "git")
        assert.eq(#got.commit, 40)
        assert.match(got.commit, "^%x+$")
    end)

    it("reports a clean tree as not dirty", function()
        assert.eq(vcs.probe(git_repo() .. "/f.txt").dirty, false)
    end)

    it("reports an uncommitted change as dirty", function()
        local dir = git_repo()
        local fh = assert(io.open(dir .. "/f.txt", "w"))
        fh:write("changed\n")
        fh:close()
        assert.eq(vcs.probe(dir .. "/f.txt").dirty, true)
    end)

    it("reports an untracked file as dirty", function()
        local dir = git_repo()
        local fh = assert(io.open(dir .. "/new.txt", "w"))
        fh:write("new\n")
        fh:close()
        assert.eq(vcs.probe(dir .. "/new.txt").dirty, true)
    end)

    it("finds the repository from a nested directory", function()
        local dir = git_repo()
        vim.fn.mkdir(dir .. "/a/b", "p")
        local fh = assert(io.open(dir .. "/a/b/deep.txt", "w"))
        fh:write("deep\n")
        fh:close()
        assert.not_nil(vcs.probe(dir .. "/a/b/deep.txt"))
    end)

    it("reports kind jj for a colocated repository", function()
        -- Detection is directory-based, so a real jj repo is not needed to
        -- exercise it; a colocated repo has both .jj and .git
        local dir = git_repo()
        vim.fn.mkdir(dir .. "/.jj", "p")
        assert.eq(vcs.probe(dir .. "/f.txt").kind, "jj")
    end)
end)
