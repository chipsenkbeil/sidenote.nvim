# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

`sidenote.nvim` annotates source code with notes stored **outside** the
annotated file. An annotation covers a whole file, a line, or a range, and
survives the code it points at being edited, moved, reformatted, or deleted.

Two uses, both intended: durable personal margin notes, and a work queue an AI
agent can read and act on.

## Where the thinking lives

| document | contents |
|---|---|
| `.claude/superpowers/specs/2026-08-18-sidenote-design.md` | the design: invariants, storage, anchoring, lifecycle, UX, agent interface |
| `.claude/superpowers/plans/*.md` | one implementation plan per slice, with tasks, tests, and code |

Both are gitignored working artifacts, not shipped docs. **Read the spec before
changing behavior**; it records why things are the way they are, including
several decisions that look arbitrary and are not.

An older spec, `2026-08-17-org-annotate-design.md`, is superseded — it assumed
org-mode was mandatory. Ignore it.

## Commands

```bash
make test            # the whole suite
make test FILE=path  # one spec file or directory
make lint            # luacheck
make fmt             # stylua, writes
make fmt-check       # stylua, fails instead of writing
make style           # the mechanical lua-style audit
make check           # all of the above, what CI runs
```

## Testing

The runner is **handrolled** — `spec/runner.lua`, run through `nvim -l`. There
is no busted, no plenary, and no luarocks; this is a Neovim plugin, and its only
development dependency is Neovim.

The assertion vocabulary is ported from doug-game so the two projects read the
same. `spec/assert.lua` is the implementation, `.addons/sidenote/testing.lua`
the LSP definitions.

**Two argument orders bite people, both the opposite of busted:**

```lua
assert.eq(actual, expected)     -- value first
assert.match(str, pattern)      -- string first, pattern second
```

`assert.match` takes a **Lua pattern**. Paths are full of `-` and `.`, which are
pattern syntax — a test asserting `assert.match(path, "^/tmp/my-store")` fails
for reasons that look impossible. Use `assert.contains` for a literal match, or
exact equality when the value is computable.

## Style

The global `lua-style` skill governs **all** Lua here, tests and comments
included. `make style` checks only the mechanical half. The rules that actually
get violated in practice:

- Every `---@field` gets a description. No exceptions.
- Never a bare `table` type; an inline table type with four or more fields gets
  promoted to a named, documented type.
- At most three positional parameters; past that, an `opts` table typed as a
  named `<owner>.Opts` class.
- Inline `--` comments run to at most two lines, are capitalized, and take no
  trailing period. `---` doc summaries are one sentence, then a blank `---`,
  then details.
- A leading underscore marks an *unused* binding only; `_x` as a private name is
  banned, `__x` is the private tier.

## Working with the stack

This is a **jj** repository. Never run mutating `git` commands in it. Work is
one change per reviewable unit; `jj new` opens the next.

**Every change must pass on its own**, not just the tip. Verify with:

```bash
for c in $(jj log --no-graph -T 'change_id.short() ++ "\n"' | head -n -1); do
  jj new "$c" >/dev/null 2>&1
  printf '%s %s\n' "$c" "$(make test 2>&1 | tail -1)"
  jj abandon @ >/dev/null 2>&1
done
```

**`jj absorb` routes by blame, not by dependency.** It is right for style fixes
and wrong for anything that adds a call to a module further up the stack: it
will happily move new wiring into the change that created the file, producing a
change that references modules which do not exist yet. That failure is
*invisible to the test suite* when the calls are behind lazy `require`s. It has
already happened once here. Check `jj st` after every absorb.

## Architecture

```
  agent (headless)        nvim UI: capture / render / preview / editor / browser
          |                              |
          +---------------+--------------+
                          |
        core: records + resolver + index cache     <- no VCS, no orgmode, no buffers
                          |
        store: <id>.<ext> prose + <id>.metadata.json
```

- **`lua/sidenote/core/` is pure** and a test enforces it: no buffers, no
  windows, no shell-outs, no filesystem beyond the index cache. This is what
  makes headless agent access and direct unit testing possible. Do not relax it.
- **An annotation is two files.** Prose the user owns, metadata the plugin owns.
  `store.update` writes metadata only, and a test proves it by making the prose
  file read-only and asserting the update still succeeds.
- **No required `setup()`.** Config is `vim.g.sidenote`, validated in
  `config.lua`, which returns defaults *alongside* any error so a bad config
  degrades rather than disabling the plugin.

## Non-obvious things that will bite you

- **Extmarks survive a buffer reload with stale positions and no invalid flag.**
  Verified. Never trust a surviving extmark; every `BufReadPost` clears the
  namespace and re-resolves from disk.
- **Never place an extmark with `strict = false`.** It silently clamps, which is
  how an annotation ends up on unrelated code. Resolve, then place, and skip
  anything out of range.
- **macOS resolves `/var` and `/tmp` into `/private`.** `buffer.target` calls
  `fs_realpath` so stored paths and project roots stay comparable; mixing
  resolved and unresolved paths breaks every project-relative path.
- **Columns belong to `range` scope alone.** A `lines` annotation stores 0, or
  the location grammar derives its scope as `range` and renders it wrongly.
- **`nvim_open_win` speaks `above`/`below`; the config speaks `top`/`bottom`.**
  `window.lua` maps between them so nvim's vocabulary never leaks into user
  config.

## Anchoring, and why the thresholds are what they are

The resolution ladder in `core/resolve.lua` runs L0 (whole-file hash) → L1
(exact at hint) → L2 (literal whole-file search) → L3 (context disambiguation) →
L4 (whitespace-normalized) → L6 (scored fuzzy). L5 is reserved for a treesitter
tier that does not exist yet.

The 0.80 accept and 0.60 guess thresholds are **measured, not guessed**.
`harness/` samples real repository history and grades placements against
`git blame --reverse`. `harness/baseline.json` holds the results with the exact
commits pinned. Regenerate it deliberately; never to make a comparison pass.

What the measurements established, and what a change here must not undo:

- The error profile must stay conservative: `false_stale` should exceed `wrong`
  at every drift depth. A wrong placement points an agent at code that was never
  the subject of the note.
- Context similarity is **graded**, not a hash comparison. Storing only
  `prefix_sha`/`suffix_sha` makes the term all-or-nothing and one inserted line
  zeroes 22% of the score. The record keeps `prefix`/`suffix` verbatim for this.
- `score.similarity` must never return the length ratio as a score. The ratio is
  an upper bound; returning it lets unrelated text of a convenient length
  outrank a real partial match.

## Status

Slices 1–5 are implemented as a ten-change stack. Plans exist for slice 6 (the
oil-style browser) and slice 7 (the agent interface); neither is started.
