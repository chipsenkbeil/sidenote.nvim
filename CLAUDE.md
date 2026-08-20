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
make docs            # regenerate README blocks and doc/sidenote.txt
make docs-check      # fail if either is stale
make check           # all of the above; run this before closing a change
```

`test` and `style` need **only Neovim** — the audit runs through `nvim -l`, not
luajit — so CI runs both against every version in its matrix. `fmt-check` needs
stylua, a single static binary CI fetches directly, and runs once.

**`lint` is the one target CI does not run.** luacheck's only real distribution
channel is luarocks, which this project does not use in either direction, so
luacheck stays a local tool. Run `make check` before closing a change; CI will
not catch a luacheck warning for you.

All four read their directory list from `LUA_DIRS` in the Makefile; adding a
directory is one edit.

## Documentation is generated

**Never edit `doc/sidenote.txt`.** It is written by `make docs` and overwritten
on every run. The sources are:

| content | lives in |
|---|---|
| all narrative prose | `README.md` |
| config defaults | `config.defaults()` |
| commands, `<Plug>` mappings | `plugin/sidenote.lua` |
| the Lua API | `---` annotations on `lua/sidenote/init.lua` |
| anchor statuses | `resolve.STATUS_NAMES` |

`scripts/gendoc.lua` expands `<!-- gen:name -->` blocks in the README from
source, then `scripts/vimdoc.lua` converts the whole README to vimdoc. Both
files are committed; `make docs-check` compares bytes and fails when either is
stale. It compares rather than diffing against the VCS, so it means the same
thing in a working tree that has other changes in it.

Two things the generator will not do for you:

- **A tag derived from a heading breaks when the heading is renamed.** Pin the
  ones a reader may have bookmarked with `<!-- vimdoc:tag sidenote-thing -->`
  above the heading. A test lists the pinned ones and fails if any disappears.
- **A tag for something that is not a section** — `:Sidenote`, `vim.g.sidenote`
  — comes from `<!-- vimdoc:anchor NAME -->`, which emits the tag verbatim on
  its own line directly above whatever follows it. Both forms feed the same
  pinned list.
- **The README must fit the page.** Code fences are indented four spaces and
  never wrapped, so a sample wider than 74 columns overflows. Prose, tables and
  headings all wrap or shrink on their own.

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
included. `make style` now checks most of the mechanical half:

- Every `---@field` gets a description. No exceptions.
- Never a bare `table` type; an inline table type with four or more fields gets
  promoted to a named, documented type.
- At most three positional parameters; past that, an `opts` table typed as a
  named `<owner>.Opts` class.
- Every parameter of a documented function carries an `@param`. Functions with
  no doc block at all are left alone, since a half-documented signature is the
  smell worth flagging.
- Inline `--` comments run to at most two lines, are capitalized, and take no
  trailing period. A bare `--` is a paragraph break and starts a fresh block; a
  comment opening on a code identifier (`math.random …`) is left uncapitalized.
- `---` doc summaries are one sentence, then a blank `---`, then details.
- A leading underscore marks an *unused* binding only; `_x` as a private name is
  banned, `__x` is the private tier.

**A file's opening comment is its header** and is exempt from all three comment
rules — it is documentation about the module, not a note bound to a statement.

What is still left to reading: whether a comment says something worth saying,
naming, and layering. Verify a change to the audit against deliberate
violations; a checker reporting zero is indistinguishable from a broken one.

## Working with the stack

This is a **jj** repository. Never run mutating `git` commands in it. Work is
one change per reviewable unit; `jj new` opens the next.

**Every change must pass on its own**, not just the tip. Verify with:

```bash
here=$(jj log --no-graph -T 'change_id.short()' -r @)
for c in $(jj log --no-graph -T 'change_id.short() ++ "\n"' -r 'all() & ~root()'); do
  jj edit "$c" || break
  printf '%-14s ' "$c"; make test 2>&1 | grep -E '[0-9]+ passed'
done
jj edit "$here"
```

**This loop only ever moves the working copy.** An earlier version created a
scratch change with `jj new "$c"` and then ran `jj abandon @`. When the `jj new`
failed — a stale id, an ambiguous prefix — `@` was still the real change, and
`abandon` destroyed it. That cost three changes before it was replaced, each
recovered with `jj op restore`. Never pair a suppressed `jj new` with
`jj abandon @`.

**`jj absorb` routes by blame, not by dependency.** It is right for style fixes
and wrong for anything that adds a call to a module further up the stack: it
will happily move new wiring into the change that created the file, producing a
change that references modules which do not exist yet. That failure is
*invisible to the test suite* when the calls are behind lazy `require`s. It has
already happened once here. Check `jj st` after every absorb.

## Architecture

```
  cli/sidenote.lua        nvim UI: capture / render / preview / editor / browser
          |                              |
     export.lua  <- the confidence gate  |
          |                              |
          +---------------+--------------+
                          |
        session (one buffer)  ·  scan (a whole project, from disk)
                          |
        core: records + resolver + index cache     <- no VCS, no orgmode, no buffers
                          |
        store: <id>.<ext> prose + <id>.metadata.json
```

- **`session` and `scan` are the two ways in.** `session.entries(bufnr)`
  resolves one buffer against its own text; `scan.project` resolves a whole
  store, preferring a loaded buffer's text and falling back to disk. The browser
  uses both, the CLI only the second. `session.entry` is the single constructor
  for the entry both produce.
- **The export gate lives in `export.lua`, not the CLI**, so every consumer
  inherits it.
- **`lua/sidenote/core/` is pure** and a test enforces it: no buffers, no
  windows, no shell-outs, no filesystem beyond the index cache. This is what
  makes headless agent access and direct unit testing possible. Do not relax it.
- **An annotation is two files.** Prose the user owns, metadata the plugin owns.
  `store.update` writes metadata only, and a test proves it by making the prose
  file read-only and asserting the update still succeeds.
- **`store.write_prose` is the one sanctioned writer of a prose file**, and it
  exists solely for the browser. Invariant 3 was amended in slice 6: prose is
  never written on capture, write-back or repair, and only ever as the direct
  application of text the user typed and then confirmed. Nothing else may call
  it.
- **The browser splits by how it fails.** `render` and `parse` are pure and
  inverse — a round-trip test pins them together, because a render that does
  not parse back reports an edit nobody made. `diff` is pure. Only `apply`
  writes, and validation that needs the filesystem lives there rather than in
  the parser.
- **`render.normalize` is the canonical form, and all three sides use it.** The
  rendered lines, the parsed result, and the browser's diff baseline. Any rule
  that lives in only one of them turns an untouched row into a phantom `write`
  that then silently rewrites the note. The summary (prose line one) stays
  trimmed at both ends; body lines keep their own indentation.
- **A header is `id kind state pen location`, and the summary lives with its
  prose**, verbatim at the margin below (2026-08-20 redesign). The concealed
  `/<id> ` marker is the grammar's only delimiter: ids are word characters, so
  prose mentioning `/etc/hosts` cannot read as a header, and everything
  unmarked is prose of the note above. Typed creates went with the old
  indentation — creation is the browser's `a` mapping. A closed fold previews
  the header's columns plus the summary via a chunked `foldtext`,
  display-only. Location being the last column is what made a path holding
  two consecutive spaces legal in a listing again.
- **A pen is a record field naming a configured highlight group** (added
  2026-08-20). `-` in the column means none; parse maps it to nil, so the
  placeholder can never diff. The parser checks only a pen's shape — whether
  it is configured is `apply`'s question, since only apply has the config.
  Pen ink colors the span; anchor health stays on the sign/underline channel.
- **While a buffer is open, its marks are the truth** (2026-08-20). Every
  paint places an invisible tracker per positioned note; once the buffer
  changes, `session.entries` reads tracked extents (tier `live`) instead of
  re-resolving, and `session.written` re-baselines an attached note to its
  extent on save — grown, shrunk or moved, the span is the user's own edit.
  A collapsed mark (span typed over, cut, or a whole-buffer format rewrite)
  and a mark placed on a guess both fall back to the resolver, which is what
  keeps `false_stale > wrong` intact. There is no edit-driven re-resolve;
  do not reintroduce one — it fights the edit in progress.
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
- **`foldtext` returns highlighted chunks on 0.10+**, which is how a closed
  row previews its columns and summary with real colors. The chunks are built
  from the buffer's own lines at draw time, so an edit made while the fold was
  open shows through the moment it closes.
- **A vim operator applies to a whole closed fold**, so `dd` on a collapsed
  browser row deletes the annotation and all its prose. The browser gets that
  for free rather than implementing it.
- **`foldminlines` defaults to 1, which leaves a one-line fold open.** A note
  with no body is exactly that, so the browser sets it to 0 to keep "every
  annotation is a closed fold" true.
- **Set fold options only once the lines exist.** A fold created after
  `foldlevel` was last set opens regardless of it, so `browser.paint` re-closes
  after filling the buffer.
- **The browser's concealed id needs `syntax` enabled.** It comes from
  `syntax/sidenote.vim`, exactly as oil does it and as the spec specifies, so
  `:syntax off` leaves raw ULIDs on every row. Verified. An extmark `conceal`
  would not have that dependency, if it ever becomes a real complaint.
- **`concealcursor` is what hides the id on the line you are on.** Without it
  every other row conceals and the cursor's row does not, which reads as a
  rendering bug rather than as a setting.

## Anchoring, and why the thresholds are what they are

The resolution ladder in `core/resolve.lua` runs L0 (whole-file hash) → L1
(exact at hint) → L2 (literal whole-file search) → L3 (context disambiguation) →
L4 (whitespace-normalized) → L6 (scored fuzzy). There is no L5: the number was
reserved for a treesitter tier and cut unbuilt; spec §6 records why, and the
corrected case for ever reviving it.

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

**Slices 1–7 are implemented**, as a stack of over fifty changes. The browser
covers a single file and the whole project, with filtering by kind, state and
anchor status. The agent interface ships as `lua/sidenote/export.lua` behind
the confidence gate, `cli/sidenote.lua` for headless runs, and an agent skill
at `skills/sidenote/SKILL.md` the README points consumers at. Write-back
(spec §6) runs on `BufWritePost` via `session.written`. Docs are generated.

A full review on 2026-08-19 fixed twenty-odd findings; the ones that were
decisions are **recorded in the spec with their reasons**: the agent `answer`
verb and its `answered` state are cut, the retention window is cut, and the
L5 treesitter tier is cut along with the never-captured `symbol`/`ts_path`
fields. The last spec'd gaps closed on 2026-08-20: capture opens the note
seeded by the `template` hook, and disk scans cache resolutions per store
under `cache_dir` (§4 records the two deviations from the original sketch).

Not built, and deliberately: MCP.
