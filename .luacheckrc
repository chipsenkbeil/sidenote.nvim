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

files[".addons/"] = {
    -- Definition files for the language server: every function is a signature
    -- with an empty body, so each of its parameters is "unused" by
    -- construction. Dropping the names would leave the signatures unreadable
    unused_args = false,
    -- Declaring the runner's globals is the whole point of the file, and
    -- `assert` is a standard one this deliberately extends
    globals = { "assert", "describe", "it", "before_each", "after_each" },
}

files["spec/"] = {
    -- The handrolled runner installs these as globals before loading a spec.
    -- Declared for `spec/` alone: a `describe` in `lua/` would be a mistake,
    -- and allowing it everywhere is how that mistake goes unnoticed
    read_globals = { "describe", "it", "before_each", "after_each", "assert" },
    -- Specs stand in for these to read what was reported, or to answer a
    -- prompt no one is at the keyboard for. `vim.fn` is writable whole:
    -- naming one field would undeclare every other one luacheck knows
    globals = { "vim.health", "vim.notify", "vim.ui.select", "vim.fn" },
}
