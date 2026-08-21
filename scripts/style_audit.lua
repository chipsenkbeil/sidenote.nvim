-- Flag mechanical lua-style violations across a file list.
--
-- Only the rules a script can check live here. Comment *content*, naming and
-- layering still need reading; a clean run is a floor, not a ceiling

local findings = {}

---@param file string
---@param line integer
---@param rule string
---@param detail string
local function report(file, line, rule, detail)
    findings[#findings + 1] = ("%s:%d  [%s] %s"):format(file, line, rule, detail)
end

---Whether `line` is a `--` comment rather than a `---` doc comment.
---@param line string|nil
---@return boolean
local function is_inline(line)
    return line ~= nil and line:match("^%s*%-%-") ~= nil and line:match("^%s*%-%-%-") == nil
end

---@param line string
---@return string
local function trimmed(line)
    return line:match("^%s*(.-)%s*$")
end

---Whether a field annotation's tail is a type alone, with no description.
---
---A bare function type reads as prose, so an undescribed one goes unflagged.
---@param rest string everything after the field name
---@return boolean
local function undescribed(rest)
    local collapsed = rest
    repeat
        local before = collapsed
        collapsed = collapsed:gsub("%b<>", ""):gsub("%b()", ""):gsub("%b{}", "")
    until collapsed == before
    return collapsed:match("%s%S") == nil
end

---Check the rules that need one line of context.
---@param file string
---@param lines string[]
local function check_lines(file, lines)
    for n, line in ipairs(lines) do
        -- Bare `table` where a precise type is required
        local bare = line:match("^%s*%-%-%-@param%s+%S+%s+table%s*$")
            or line:match("^%s*%-%-%-@return%s+table%s*$")
        if bare then
            report(file, n, "bare-type", trimmed(line))
        end

        -- @field carrying a type but no description
        local field = line:match("^%s*%-%-%-@field%s+(.*)$")
        if field then
            local label, rest = field:match("^(private%s+%S+)%s+(.-)%s*$")
            if not label then
                label, rest = field:match("^(%S+)%s+(.-)%s*$")
            end
            if label and rest and rest ~= "" and undescribed(rest) then
                report(file, n, "field-no-desc", ("%s %s"):format(label, rest))
            end
        end

        -- Inline table type with four or more fields must become a named type
        local inline = line:match("%-%-%-@param%s+%S+%s+({.+})")
            or line:match("%-%-%-@return%s+({.+})")
        if inline then
            local commas = select(2, inline:gsub(",", ","))
            if commas >= 3 then
                report(file, n, "inline-type-4+", ("%d fields"):format(commas + 1))
            end
        end

        -- More than three positional parameters
        local params = line:match("^%s*function%s+[%w_%.:]+%(([^)]*)%)")
        if params and params ~= "" then
            local count = select(2, params:gsub(",", ",")) + 1
            local has_opts = params:match("opts%s*$") ~= nil
            if count > 3 and not has_opts then
                report(file, n, "positional-4+", ("%d params: %s"):format(count, params))
            end
        end

        -- Doc summary running straight into details with no blank --- line
        if line:match("^%-%-%-%a") and lines[n - 1] and not lines[n - 1]:match("^%-%-%-") then
            local next_line = lines[n + 1]
            if next_line and next_line:match("^%-%-%-%a") and line:match("%.%s") then
                report(file, n, "summary-run-on", line:sub(1, 60))
            end
        end

        -- A single leading underscore marks an unused binding, never privacy
        local private_field = line:match("^%s*%-%-%-@field%s+private%s+(_%a[%w_]*)")
        if private_field then
            report(file, n, "underscore-private", private_field)
        end
        local private_fn = line:match("^%s*function%s+[%w_]+[%.:](_%a[%w_]*)%s*%(")
        if private_fn then
            report(file, n, "underscore-private", private_fn)
        end
        local private_access = line:match("self%.(_%a[%w_]*)")
        if private_access then
            report(file, n, "underscore-private", "self." .. private_access)
        end
    end
end

---Whether `line` is a bare `--`, which ends one comment block and opens the next.
---@param line string|nil
---@return boolean
local function is_break(line)
    return is_inline(line) and line:match("^%s*%-%-%s*$") ~= nil
end

---Whether a comment opens on something that is code rather than a word.
---
---`math.random without a seed…` is right as written; capitalizing it would
---name a different thing.
---@param head string
---@return boolean
local function opens_on_code(head)
    local first_word = head:match("^(%S+)")
    return first_word ~= nil and first_word:match("[%._:(]") ~= nil
end

---Check the shape rules for each run of inline comment lines.
---
---A comment opening the file is its header, and is exempt from all of them.
---@param file string
---@param lines string[]
local function check_comment_blocks(file, lines)
    local n = 1
    local in_header = is_inline(lines[1])

    while n <= #lines do
        if not is_inline(lines[n]) or is_break(lines[n]) then
            if not is_inline(lines[n]) then
                in_header = false
            end
            n = n + 1
        else
            local first = n
            while is_inline(lines[n]) and not is_break(lines[n]) do
                n = n + 1
            end
            local last = n - 1

            if not in_header then
                if last - first + 1 > 2 then
                    local count = last - first + 1
                    report(
                        file,
                        first,
                        "comment-too-long",
                        ("%d lines; shrink it or restructure the code"):format(count)
                    )
                end

                local head = lines[first]:match("^%s*%-%-%s*(.*)$")
                if head and head:match("^%l") and not opens_on_code(head) then
                    report(file, first, "comment-lowercase", head:sub(1, 50))
                end

                local tail = lines[last]:match("^%s*%-%-%s*(.*)$")
                if tail and tail:match("%.$") and not tail:match("%.%.%.$") then
                    report(file, last, "comment-trailing-period", tail:sub(-45))
                end
            end
        end
    end
end

---Check that every parameter of a documented function carries an `@param`.
---
---Only functions that already have a doc block are checked: a half-documented
---signature is the smell, and flagging every undocumented local would drown it.
---@param file string
---@param lines string[]
local function check_params(file, lines)
    for n, line in ipairs(lines) do
        local params = line:match("^%s*local function [%w_]+%(([^)]*)%)")
            or line:match("^%s*function [%w_%.:]+%(([^)]*)%)")
        if params and params ~= "" then
            local documented, has_doc = {}, false
            local above = n - 1
            while above > 0 and lines[above]:match("^%s*%-%-%-") do
                has_doc = true
                local name = lines[above]:match("@param%s+([%w_]+)")
                if name then
                    documented[name] = true
                end
                above = above - 1
            end

            if has_doc then
                for name in params:gmatch("[%w_]+") do
                    if not documented[name] and name:sub(1, 1) ~= "_" and name ~= "self" then
                        report(file, n, "param-undocumented", name)
                    end
                end
            end
        end
    end
end

for _, file in ipairs(arg) do
    local lines = {}
    for line in io.lines(file) do
        lines[#lines + 1] = line
    end
    check_lines(file, lines)
    check_comment_blocks(file, lines)
    check_params(file, lines)
end

table.sort(findings)
for _, finding in ipairs(findings) do
    print(finding)
end
print(("\n%d findings"):format(#findings))

os.exit(#findings == 0 and 0 or 1)
