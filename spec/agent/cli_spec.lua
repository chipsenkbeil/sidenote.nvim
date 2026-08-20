local capture = require("sidenote.capture")
local cli = require("cli.sidenote")
local store = require("sidenote.store")

---@return sidenote.Config
local function opts()
    return {
        filetype = "org",
        strategy = { "project" },
        project_dir = ".annotations",
        global_dir = vim.fn.tempname(),
        indicator = { style = "sign" },
        preview = { style = "float", max_lines = 20 },
        editor = { style = "split", position = "right", size = 60 },
    }
end

local ALPHA = { "local M = {}", "", "function M.f()", "  return 1", "end" }
local BETA = { "-- beta", "local x = 1", "return x" }

---@return string root
local function project()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.annotations", "p")
    for name, lines in pairs({ ["alpha.lua"] = ALPHA, ["beta.lua"] = BETA }) do
        local fh = assert(io.open(root .. "/" .. name, "w"))
        fh:write(table.concat(lines, "\n") .. "\n")
        fh:close()
    end
    return assert(vim.uv.fs_realpath(root))
end

---@param root string
---@param name string
---@param capture_opts sidenote.capture.Opts everything but the config
---@param prose string[]
---@return string id
local function annotate_with(root, name, capture_opts, prose)
    local path = root .. "/" .. name
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, path)
    local fh = assert(io.open(path, "r"))
    local body = fh:read("*a")
    fh:close()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(body:gsub("\n$", ""), "\n"))

    local cfg = opts()
    capture_opts.config = cfg
    local result = assert(capture.run(bufnr, capture_opts))
    vim.api.nvim_buf_delete(bufnr, { force = true })

    local note = assert(io.open(store.prose_path(result.root, result.id, cfg.filetype), "w"))
    note:write(table.concat(prose, "\n") .. "\n")
    note:close()
    return result.id
end

---@param root string
---@param name string
---@param line integer
---@param prose string[]
---@return string id
local function annotate(root, name, line, prose)
    return annotate_with(root, name, { scope = "lines", range = { line, 0, line, 0 } }, prose)
end

---Run the CLI the way a shell would, capturing what it printed.
---@param argv string[]
---@return integer code
---@return string[] out
---@return string[] err
local function run(argv)
    local out, err = {}, {}
    local code = cli.main(argv, {
        config = opts(),
        write = function(line)
            out[#out + 1] = line
        end,
        fail = function(line)
            err[#err + 1] = line
        end,
    })
    return code, out, err
end

describe("cli export", function()
    it("prints a parseable document for a project", function()
        local root = project()
        annotate(root, "alpha.lua", 4, { "the note" })

        local code, out = run({ "export", root })
        assert.eq(code, 0)
        local doc = vim.json.decode(table.concat(out, "\n"))
        assert.eq(#doc.annotations, 1)
        assert.eq(doc.annotations[1].prose, "the note")
    end)

    it("prints an empty document for a project with no annotations", function()
        local code, out = run({ "export", project() })
        assert.eq(code, 0)
        assert.eq_deep(vim.json.decode(table.concat(out, "\n")).annotations, {})
    end)

    it("withholds a position for code that no longer exists", function()
        local root = project()
        annotate(root, "beta.lua", 2, { "about deleted code" })
        os.remove(root .. "/beta.lua")

        local _, out = run({ "export", root })
        local record = vim.json.decode(table.concat(out, "\n")).annotations[1]
        assert.truthy(record.code_no_longer_exists)
        assert.is_nil(record.line_start)
    end)
end)

describe("cli list", function()
    it("prints one line per annotation", function()
        local root = project()
        annotate(root, "alpha.lua", 4, { "first note" })
        annotate(root, "beta.lua", 2, { "second note" })

        local code, out = run({ "list", root })
        assert.eq(code, 0)
        assert.eq(#out, 2)
    end)

    it("puts the location first, so the output is greppable and jumpable", function()
        local root = project()
        annotate(root, "alpha.lua", 4, { "the note" })

        local _, out = run({ "list", root })
        assert.match(out[1], "^alpha%.lua:4%s")
        assert.contains(out[1], "the note")
    end)

    it("lists a file-wide annotation by its path alone", function()
        -- A placed file-scope annotation has a status but no lines, so its
        -- location column is the bare path, not a formatted position
        local root = project()
        annotate_with(root, "alpha.lua", { scope = "file" }, { "about the whole file" })

        local code, out = run({ "list", root })
        assert.eq(code, 0)
        assert.match(out[1], "^alpha%.lua\t")
        assert.contains(out[1], "attached")
        assert.contains(out[1], "about the whole file")
    end)

    it("names the status instead of a location when there is none", function()
        local root = project()
        annotate(root, "beta.lua", 2, { "about deleted code" })
        os.remove(root .. "/beta.lua")

        local _, out = run({ "list", root })
        assert.match(out[1], "^beta%.lua%s")
        assert.contains(out[1], "filegone")
    end)

    it("shows only the first line of a multi-line note", function()
        local root = project()
        annotate(root, "alpha.lua", 4, { "the summary", "a body line" })

        local _, out = run({ "list", root })
        assert.eq(#out, 1)
        assert.falsy(out[1]:find("a body line", 1, true))
    end)

    it("filters by status", function()
        local root = project()
        annotate(root, "alpha.lua", 4, { "still attached" })
        annotate(root, "beta.lua", 2, { "about deleted code" })
        os.remove(root .. "/beta.lua")

        local code, out = run({ "list", root, "--status", "filegone" })
        assert.eq(code, 0)
        assert.eq(#out, 1)
        assert.contains(out[1], "about deleted code")
    end)

    it("prints nothing when a filter matches nothing, and still succeeds", function()
        local root = project()
        annotate(root, "alpha.lua", 4, { "the note" })

        local code, out = run({ "list", root, "--status", "orphaned" })
        assert.eq(code, 0)
        assert.eq_deep(out, {})
    end)

    it("rejects a status that is not one the resolver produces", function()
        local code, _, err = run({ "list", project(), "--status", "banana" })
        assert.neq(code, 0)
        assert.contains(table.concat(err, "\n"), "banana")
    end)
end)

describe("cli argument handling", function()
    it("exits non-zero and explains an unknown subcommand", function()
        local code, out, err = run({ "frobnicate", project() })
        assert.neq(code, 0)
        assert.eq_deep(out, {})
        assert.contains(table.concat(err, "\n"), "frobnicate")
    end)

    it("exits non-zero when no subcommand is given", function()
        local code, _, err = run({})
        assert.neq(code, 0)
        assert.gt(#err, 0)
    end)

    it("defaults to the working directory when no project is named", function()
        local code = run({ "list" })
        assert.eq(code, 0)
    end)

    it("succeeds on a directory with no store, because nothing to do is not a failure", function()
        local loose = vim.fn.tempname()
        vim.fn.mkdir(loose, "p")
        local code, out = run({ "list", loose })
        assert.eq(code, 0)
        assert.eq_deep(out, {})
    end)
end)

describe("cli run as a script", function()
    -- The in-process tests inject a writer, so only running the real thing can
    -- prove which stream the output lands on
    ---@param argv string[]
    ---@return string stdout
    local function shell(argv)
        local command = { "nvim", "--headless", "-l", "cli/sidenote.lua" }
        vim.list_extend(command, argv)
        return vim.fn.system(command)
    end

    it("prints its document on stdout, where a pipe can reach it", function()
        -- `print` under --headless -l goes to stderr, so redirecting stdout to
        -- a file would capture nothing
        local root = project()
        annotate(root, "alpha.lua", 4, { "the note" })

        local out = shell({ "export", root })
        local doc = vim.json.decode(out)
        assert.eq(#doc.annotations, 1)
    end)

    it("prints its listing on stdout too", function()
        local root = project()
        annotate(root, "alpha.lua", 4, { "the note" })
        assert.contains(shell({ "list", root }), "alpha.lua:4")
    end)

    it("finds prose written under a different filetype than the one configured", function()
        -- A headless run has no user config, so it asks for the default `txt`
        -- while the store holds `.org`
        local root = project()
        annotate(root, "alpha.lua", 4, { "written as org" })
        assert.contains(shell({ "list", root }), "written as org")
    end)
end)

describe("cli entry point", function()
    ---@return string
    local function source()
        local fh = assert(io.open("cli/sidenote.lua", "r"))
        local src = fh:read("*a")
        fh:close()
        return src
    end

    it("guards its run on arg[0], so requiring it cannot start one", function()
        -- The test runner populates _G.arg too, and this spec requires the
        -- module directly
        assert.contains(source(), "arg[0]")
    end)

    it("bootstraps its own module search path", function()
        assert.contains(source(), "package.path")
    end)
end)
