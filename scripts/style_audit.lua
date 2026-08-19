-- Flag mechanical lua-style violations across a file list.
--
-- Covers only the rules a script can check. Comment content, naming, and
-- visibility still need reading; `make style` is a floor, not a ceiling.
local files = {}
for i = 1, #arg do
    files[#files + 1] = arg[i]
end

local findings = {}

local function report(file, line, rule, detail)
    findings[#findings + 1] = ("%s:%d  [%s] %s"):format(file, line, rule, detail)
end

for _, file in ipairs(files) do
    local lines = {}
    for line in io.lines(file) do
        lines[#lines + 1] = line
    end

    for n, line in ipairs(lines) do
        -- Bare `table` / `any` where a precise type is required.
        local bare = line:match("^%s*%-%-%-@param%s+%S+%s+table%s*$")
            or line:match("^%s*%-%-%-@return%s+table%s*$")
        if bare then
            report(file, n, "bare-type", line:match("^%s*(.-)%s*$"))
        end

        -- @field with a type but no description.
        local fname, ftype = line:match("^%s*%-%-%-@field%s+(%S+)%s+(%S+)%s*$")
        if fname and fname ~= "private" then
            report(file, n, "field-no-desc", ("%s %s"):format(fname, ftype))
        end
        local pname, ptype = line:match("^%s*%-%-%-@field%s+private%s+(%S+)%s+(%S+)%s*$")
        if pname then
            report(file, n, "field-no-desc", ("private %s %s"):format(pname, ptype))
        end

        -- Inline table type with four or more fields must become a named type.
        local inline = line:match("%-%-%-@param%s+%S+%s+({.+})")
            or line:match("%-%-%-@return%s+({.+})")
        if inline then
            local commas = select(2, inline:gsub(",", ","))
            if commas >= 3 then
                report(file, n, "inline-type-4+", ("%d fields"):format(commas + 1))
            end
        end

        -- More than three positional parameters.
        local params = line:match("^%s*function%s+[%w_%.:]+%(([^)]*)%)")
        if params and params ~= "" then
            local count = select(2, params:gsub(",", ",")) + 1
            local has_opts = params:match("opts%s*$") ~= nil
            if count > 3 and not has_opts then
                report(file, n, "positional-4+", ("%d params: %s"):format(count, params))
            end
        end

        -- Doc summary running straight into details with no blank --- line.
        if line:match("^%-%-%-%a") and lines[n - 1] and not lines[n - 1]:match("^%-%-%-") then
            local nxt = lines[n + 1]
            if nxt and nxt:match("^%-%-%-%a") and line:match("%.%s") then
                report(file, n, "summary-run-on", line:sub(1, 60))
            end
        end
    end
end

table.sort(findings)
for _, finding in ipairs(findings) do
    print(finding)
end
print(("\n%d findings"):format(#findings))
