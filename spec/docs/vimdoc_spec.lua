local vimdoc = require("scripts.vimdoc")

---Render `markdown` as the lines of a help file.
---@param markdown string
---@param opts? scripts.vimdoc.Opts front matter, defaulting to a demo plugin
---@return string[]
local function render(markdown, opts)
    local lines = {}
    for line in (markdown .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    return vimdoc.render(
        lines,
        opts or { project = "demo", description = "a demo plugin", version = "NVIM v0.11.0" }
    )
end

---Render `markdown` as one help-file string.
---@param markdown string
---@return string
local function text(markdown)
    return table.concat(render(markdown), "\n")
end

---Find the rendered line carrying `needle`, and the one before it.
---
---Raises when nothing matches.
---@param lines string[]
---@param needle string Lua pattern the wanted line matches
---@return string line
---@return string previous line above the match, empty when it is the first
local function locate(lines, needle)
    for i, line in ipairs(lines) do
        if line:find(needle) then
            return line, lines[i - 1] or ""
        end
    end
    error("not rendered: " .. needle)
end

describe("vimdoc headings", function()
    it("turns a level-two heading into a numbered section with a rule", function()
        local heading, above = locate(render("## Getting started\n\nSome prose."), "^1%. Getting")
        assert.contains(heading, "1. Getting started")
        assert.eq(above, ("="):rep(78))
    end)

    it("right-aligns a derived tag on the heading line", function()
        local heading = locate(render("## Getting started\n"), "^1%. Getting")
        assert.contains(heading, "*demo-getting-started*")
        assert.eq(#heading, 78)
    end)

    it("honours an explicit tag directive over the derived one", function()
        -- A tag is a promise to users, and a heading rename must not break it
        local out = render("<!-- vimdoc:tag demo-start -->\n## Getting started\n")
        assert.contains(locate(out, "^1%. Getting"), "*demo-start*")
        assert.falsy(table.concat(out, "\n"):find("demo-getting-started", 1, true))
    end)

    it("renders a level-three heading as a subsection with its own tag", function()
        local out = render("## Storage\n\n### Where notes live\n")
        assert.contains(table.concat(out, "\n"), "WHERE NOTES LIVE")
        assert.contains(table.concat(out, "\n"), "*demo-where-notes-live*")
    end)

    it("treats a level-one heading as the document title, not a section", function()
        -- Repeating the project name as a section pushes every real one down
        local out = text("# demo.nvim\n\n## First\n\nprose\n")
        assert.contains(out, "1. First")
        assert.falsy(out:find("DEMO.NVIM", 1, true))
        assert.falsy(out:find("1. demo.nvim", 1, true))
    end)

    it("numbers sections in the order they appear", function()
        local out = text("## First\n\n## Second\n\n## Third\n")
        assert.contains(out, "1. First")
        assert.contains(out, "2. Second")
        assert.contains(out, "3. Third")
    end)
end)

describe("vimdoc front matter", function()
    it("opens with the help-file tag and the description", function()
        local out = render("## Anything\n")
        assert.contains(out[1], "*demo.txt*")
        assert.contains(out[1], "a demo plugin")
    end)

    it("carries no date, so regenerating an unchanged source changes nothing", function()
        -- A build-time stamp would make the staleness gate fail on every run
        local first = text("## Anything\n")
        local second = text("## Anything\n")
        assert.eq(first, second)
        assert.falsy(first:find("Last change", 1, true))
    end)

    it("ends with a modeline so the file renders as help", function()
        local out = render("## Anything\n")
        assert.eq(out[#out], "vim:tw=78:ts=8:ft=help:norl:")
    end)

    it("keeps every line inside the page, however long a heading is", function()
        local long = "## " .. ("Extremely wordy section title "):rep(3) .. "\n\nprose\n"
        local out = render(long)
        for _, line in ipairs(out) do
            assert.lte(#line, 78, "overlong line: " .. line)
        end
        assert.contains(table.concat(out, "\n"), "*demo-extremely-wordy")
    end)

    it("builds a table of contents from the sections", function()
        local out = text("## First\n\nprose\n\n## Second\n\nprose\n")
        assert.contains(out, "*demo-contents*")
        assert.contains(out, "|demo-first|")
        assert.contains(out, "|demo-second|")
    end)
end)

describe("vimdoc prose", function()
    it("wraps a paragraph to 78 columns", function()
        local long = ("word "):rep(40)
        for _, line in ipairs(render("## S\n\n" .. long)) do
            assert.lte(#line, 78, "overlong line: " .. line)
        end
    end)

    it("keeps paragraphs apart", function()
        local out = text("## S\n\nFirst para.\n\nSecond para.")
        assert.contains(out, "First para.\n\nSecond para.")
    end)

    it("strips bold, since vimdoc has no such thing", function()
        assert.contains(text("## S\n\nThis is **important** here."), "This is important here.")
    end)

    it("keeps inline code as plain backticks, which help highlights natively", function()
        assert.contains(text("## S\n\nCall `setup()` first."), "`setup()`")
    end)

    it("renders a link as its text followed by the target", function()
        local out = text("## S\n\nSee [the docs](https://example.com/x).")
        assert.contains(out, "the docs <https://example.com/x>")
    end)

    it("turns a help reference into a real vimdoc link", function()
        assert.contains(text("## S\n\nRun `:help demo-thing` now."), "|demo-thing|")
    end)
end)

describe("vimdoc code blocks", function()
    it("fences a code block with the language, the way help files do", function()
        local out = text("## S\n\n```lua\nlocal x = 1\n```\n")
        assert.contains(out, ">lua\n    local x = 1\n<")
    end)

    it("fences an unlabelled block without a language", function()
        assert.contains(text("## S\n\n```\nplain\n```\n"), ">\n    plain\n<")
    end)

    it("never wraps inside a code block", function()
        local long = ("x"):rep(120)
        assert.contains(text("## S\n\n```\n" .. long .. "\n```\n"), long)
    end)
end)

describe("vimdoc tables", function()
    it("renders a table as aligned columns", function()
        local out = text("## S\n\n| name | meaning |\n|---|---|\n| a | first |\n| bb | second |\n")
        assert.contains(out, "a")
        assert.contains(out, "first")
        assert.falsy(out:find("|---|", 1, true), "the separator row is not content")
    end)

    it("keeps a table within 78 columns", function()
        local row = "| " .. ("long value "):rep(6) .. " | " .. ("another "):rep(6) .. " |\n"
        local md = "## S\n\n| a | b |\n|---|---|\n" .. row
        for _, line in ipairs(render(md)) do
            assert.lte(#line, 78, "overlong table line: " .. line)
        end
    end)
end)

describe("vimdoc directives", function()
    it("drops content marked as README-only", function()
        local out = text(
            "## S\n\n<!-- vimdoc:ignore-start -->\nbadges here\n<!-- vimdoc:ignore-end -->\n\nkept"
        )
        assert.falsy(out:find("badges here", 1, true))
        assert.contains(out, "kept")
    end)

    it("leaves an unknown comment out of the output entirely", function()
        assert.falsy(text("## S\n\n<!-- just a note -->\n\nprose"):find("just a note", 1, true))
    end)

    it("gives an anchor directive a right-aligned tag of its own", function()
        -- A slugified tag would not be the `:Demo` a reader types
        local line = locate(render("## S\n\n<!-- vimdoc:anchor :Demo -->\n\nprose\n"), "%*:Demo%*")
        assert.contains(line, "*:Demo*")
        assert.eq(#line, 78)
    end)

    it("sits an anchor directly on the item it names", function()
        -- A blank line between would read as a tag for the whole section
        local out = render("## S\n\n<!-- vimdoc:anchor vim.g.demo -->\n\nprose here\n")
        local _, above = locate(out, "^prose here$")
        assert.contains(above, "*vim.g.demo*")
    end)
end)
