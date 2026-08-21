-- A direct `nvim --headless -l cli/sidenote.lua` has no module search path yet
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = ("%s/lua/?.lua;%s/lua/?/init.lua;%s/?.lua;%s"):format(root, root, root, package.path)

local config = require("sidenote.config")
local export = require("sidenote.export")
local location = require("sidenote.location")
local resolve = require("sidenote.core.resolve")

---@class cli.sidenote.Opts
---@field config? sidenote.Config resolved configuration, read from vim.g when omitted
---@field write? fun(line: string) prints a result line, defaults to stdout
---@field fail? fun(line: string) prints a problem, defaults to stderr

---Headless access to a project's annotations.
---
---The confidence gate lives in `export`, so an annotation read here and one
---read through the Lua API say the same thing.
---@class cli.sidenote
local M = {}

local USAGE = table.concat({
    "usage: nvim --headless -l cli/sidenote.lua <command> [project] [options]",
    "",
    "  export <project>                 the whole store as JSON",
    "  list <project> [--status <s>] [--change <p>] [--commit <p>]",
    "                                   one line per annotation",
    "",
    ("A status is one of %s."):format(table.concat(resolve.STATUS_NAMES, ", ")),
    "Anything but attached or drifted is reported without line numbers, on",
    "purpose: the code it was written against no longer exists as written.",
}, "\n")

---Split `argv` into a command, a project, and the `--flag` values.
---@param argv string[] arguments given after the script name
---@return string command first positional, empty when there is none
---@return string project second positional, defaulting to the working directory
---@return table<string, string> flags mapping of flag name -> the argument after it
local function parse(argv)
    local positional, flags = {}, {}
    local i = 1
    while i <= #argv do
        local flag = argv[i]:match("^%-%-(.+)$")
        if flag then
            flags[flag] = argv[i + 1]
            i = i + 2
        else
            positional[#positional + 1] = argv[i]
            i = i + 1
        end
    end
    return positional[1] or "", positional[2] or vim.fn.getcwd(), flags
end

---Format `record` as one greppable line, location first so an editor can jump to it.
---
---An annotation with no lines — file-wide, or one the gate withheld — shows its
---path where the position would be, rather than a number nothing stands behind.
---@param record sidenote.export.Record
---@return string
local function summarize(record)
    local where = record.path
    if record.line_start then
        where = location.format({
            path = record.path,
            scope = "lines",
            line_start = record.line_start,
            line_end = record.line_end,
            col_start = 0,
            col_end = 0,
        })
    end
    local summary = record.prose:match("^([^\n]*)") or ""
    return ("%s\t%s\t%s\t%s\t%s"):format(where, record.status, record.kind, record.state, summary)
end

---Report whether `record` satisfies every VCS id prefix named in `flags`.
---
---A prefix matches the way jj and git themselves accept one; an unstamped note
---belongs to no change and never matches.
---@param record sidenote.export.Record
---@param flags table<string, string> mapping of flag name -> the argument after it
---@return boolean
local function stamped(record, flags)
    for _, key in ipairs({ "change", "commit" }) do
        local want = flags[key]
        if want and (record[key] == nil or record[key]:sub(1, #want) ~= want) then
            return false
        end
    end
    return true
end

---Run one command, print what it produced, and report the process exit code.
---
---Nothing to show is not a failure: a project with no store, and a filter that
---matched nothing, both succeed silently.
---@param argv string[] arguments given after the script name
---@param opts? cli.sidenote.Opts
---@return integer code 0 on success, 2 on a usage error
function M.main(argv, opts)
    opts = opts or {}
    -- Not `print`: under `--headless -l` that goes to stderr, so redirecting
    -- stdout to a file would capture nothing at all
    local write = opts.write or function(line)
        io.stdout:write(line .. "\n")
    end
    local fail = opts.fail or function(line)
        io.stderr:write(line .. "\n")
    end

    local command, project, flags = parse(argv)
    if command == "" then
        fail(USAGE)
        return 2
    end
    if command ~= "export" and command ~= "list" then
        fail(("unknown command %q\n\n%s"):format(command, USAGE))
        return 2
    end

    local wanted = flags.status
    if wanted and not resolve.STATUSES[wanted] then
        fail(
            ("unknown status %q; expected one of %s"):format(
                wanted,
                table.concat(resolve.STATUS_NAMES, ", ")
            )
        )
        return 2
    end

    local cfg = opts.config or config.get()
    local doc = export.project({ path = project, config = cfg })

    if command == "export" then
        write(vim.json.encode(doc))
        return 0
    end

    for _, record in ipairs(doc.annotations) do
        if (not wanted or record.status == wanted) and stamped(record, flags) then
            write(summarize(record))
        end
    end
    return 0
end

-- Guarded on arg[0]: any `nvim -l` script populates _G.arg, and a require of
-- this module from one of those must not kick off a run
if _G.arg and _G.arg[0] and _G.arg[0]:match("sidenote%.lua$") then
    local argv = {}
    for i = 1, #_G.arg do
        argv[i] = _G.arg[i]
    end
    os.exit(M.main(argv))
end

return M
