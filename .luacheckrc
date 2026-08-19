-- luacheck configuration.
--
-- A file rather than flags on the Makefile's luacheck line, so an editor's
-- luacheck integration reads the same rules the command line does, and so the
-- test vocabulary can be scoped to the tests instead of allowed everywhere.

std = "lua51"
cache = true

-- Neovim's API, available to every file here. `vim` itself is read-only, so a
-- typo like `vim.api = x` is caught, but the option tables are assigned to
-- constantly and have to be declared writable by name
read_globals = { "vim" }
globals = {
    "vim.b",
    "vim.bo",
    "vim.g",
    "vim.go",
    "vim.o",
    "vim.opt",
    "vim.opt_local",
    "vim.w",
    "vim.wo",
}

-- Long lines are the formatter's business; stylua wraps what it can, and what
-- it cannot is a string or an annotation that has to stay whole
max_line_length = 120

files["spec/"] = {
    -- The handrolled runner installs these as globals before loading a spec.
    -- Declared for `spec/` alone: a `describe` in `lua/` would be a mistake,
    -- and allowing it everywhere is how that mistake goes unnoticed
    read_globals = { "describe", "it", "before_each", "after_each", "assert" },
    -- The health spec stands in for `vim.health` to read what a check reported
    globals = { "vim.health" },
}
