# sidenote.nvim

Annotate source code with notes stored outside the annotated file. A note
attaches to a whole file, a line, or a range, and survives the code it points at
being edited, moved, reformatted, or deleted.

Two uses, both intended: durable personal margin notes, and a work queue an AI
agent can read and act on.

<!-- vimdoc:tag sidenote-why -->

## Why notes live outside the file

A comment changes the code. A note does not. You can annotate a vendored
dependency, a file you have no business editing, or a function you are still
deciding about, and nothing you write lands in a diff.

The cost is anchoring: a note has to find its code again after the code moves.
See [Anchoring](#anchoring).

## Requirements

Neovim 0.11 or newer, for `vim.fs.relpath`. No dependencies.

Optional, each independently useful:

| optional | buys |
|---|---|
| nvim-orgmode | org editing, because the prose file ends in `.org` |
| git or jj | provenance stamping, never used for resolution |

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "chipsenkbeil/sidenote.nvim" }
```

There is no `setup()` to call. Configuration is `vim.g.sidenote`, and every
field has a default.

## Getting started

Map what you want. A full set that avoids the common collisions — `]s` is
spell, and `]a`, `]b`, `]q`, `]d` are Neovim defaults:

```lua
vim.keymap.set({ "n", "x" }, "<Leader>sa", "<Plug>(SidenoteAdd)")
vim.keymap.set("n", "<Leader>sA", "<Plug>(SidenoteAddFile)")
vim.keymap.set("n", "<Leader>sv", "<Plug>(SidenoteView)")
vim.keymap.set("n", "<Leader>so", "<Plug>(SidenoteOpen)")
vim.keymap.set("n", "<Leader>sb", "<Plug>(SidenoteBrowse)")
vim.keymap.set("n", "<Leader>sB", "<Plug>(SidenoteBrowseProject)")
vim.keymap.set("n", "<Leader>sr", "<Plug>(SidenoteRefresh)")
vim.keymap.set("n", "<Leader>sh", "<Plug>(SidenoteToggleHighlight)")
vim.keymap.set("n", "<Leader>sf", "<Plug>(SidenoteFollow)")
vim.keymap.set("n", "<Leader>sp", "<Plug>(SidenotePen)")
vim.keymap.set("n", "<Leader>sm", "<Plug>(SidenoteMenu)")
vim.keymap.set("n", "]n", "<Plug>(SidenoteViewNext)")
vim.keymap.set("n", "[n", "<Plug>(SidenoteViewPrev)")
```

Annotate a line and the note opens beside it; write, save. A sign appears in
the gutter. Edit the code around it, reformat it, move it down the file: the
sign follows.

## Mappings

No default mappings are installed.

<!-- gen:mappings -->
| mapping | does |
|---|---|
| `<Plug>(SidenoteAdd)` | Annotate the current line or selection |
| `<Plug>(SidenoteAddFile)` | Annotate the whole file |
| `<Plug>(SidenoteBrowse)` | Open the editable listing of this file's annotations |
| `<Plug>(SidenoteBrowseProject)` | Open the editable listing of every annotation in the project |
| `<Plug>(SidenoteRefresh)` | Re-resolve and repaint annotations |
| `<Plug>(SidenoteToggleHighlight)` | Toggle range highlights in this buffer |
| `<Plug>(SidenoteFollow)` | Toggle the note editor following the cursor |
| `<Plug>(SidenotePen)` | Rotate the active pen for new notes |
| `<Plug>(SidenoteMenu)` | Open the menu for the note under the cursor |
| `<Plug>(SidenoteCycleKind)` | Flip the note under the cursor between note and todo |
| `<Plug>(SidenoteCycleState)` | Cycle the state of the note under the cursor |
| `<Plug>(SidenoteCycleStateBack)` | Cycle the state of the note under the cursor, backward |
| `<Plug>(SidenoteCyclePen)` | Cycle the pen of the note under the cursor |
| `<Plug>(SidenoteCyclePenBack)` | Cycle the pen of the note under the cursor, backward |
| `<Plug>(SidenoteView)` | Preview the annotation under the cursor |
| `<Plug>(SidenoteOpen)` | Open the annotation under the cursor for writing |
| `<Plug>(SidenoteViewNext)` | Jump to the next annotation and preview it |
| `<Plug>(SidenoteViewPrev)` | Jump to the previous annotation and preview it |
<!-- /gen:mappings -->

Inside a browser buffer only:

| mapping | does |
|---|---|
| `<CR>` | open this note's prose for writing |
| `gf` | jump to the code the note is about |
| `a` | create a note on a file, and open it |
| `t` `T` | cycle state forward and back — or kind or pen, on their columns |
| `fk` `fs` `fa` | filter by kind, state, or anchor status |
| `ff` | filter by path substring |
| `fc` | clear every filter |
| `<Tab>` `<S-Tab>` | move between columns |
| `-` | widen to every annotation in the project |
| `?` | this table, as a float |

Fold verbs need no mapping. The folds are real.

## Commands

<!-- vimdoc:anchor :Sidenote -->

<!-- gen:commands -->
```vim
:Sidenote add | browse | project | refresh | view | open | next
          | prev | highlight | follow | pen
```
<!-- /gen:commands -->

`browse` and `project` take filters, which complete, validate, and combine:

```vim
:Sidenote browse  kind=todo
:Sidenote project status=orphaned
:Sidenote project kind=todo state=open
:Sidenote project path=lua/net
```

`project` also takes a path, defaulting to the project holding the current
file. `add scope=file` annotates the whole file rather than a line.

## Configuration

<!-- vimdoc:anchor vim.g.sidenote -->

<!-- gen:config -->
```lua
vim.g.sidenote = {
    -- Extension and filetype of prose files
    filetype = "txt",

    -- Stores to use, tried in order; also the read order
    strategy = { "project", "global" },
    global_dir = vim.fn.stdpath("data") .. "/sidenote",
    project_dir = ".sidenote",

    -- Where scans cache resolutions; never inside a store, which may be
    -- committed
    cache_dir = vim.fn.stdpath("cache") .. "/sidenote",

    -- The pen fresh notes pick up; `:Sidenote pen` changes it live
    -- pen = "yellow",

    -- Pens a note can carry, each naming the highlight group its ink
    -- uses; custom entries merge over these
    pens = {
        yellow = "SidenotePenYellow",
        coral = "SidenotePenCoral",
        blue = "SidenotePenBlue",
        green = "SidenotePenGreen",
    },

    -- Style: sign | virt_text | highlight | underline | summary | none.
    -- The overlay: off | on (toggleable defaults) | always | never
    indicator = { style = "sign", highlight = "on" },

    -- Where a note appears when glanced at:
    -- float | virt_lines | split | none
    preview = { style = "float", max_lines = 20 },

    -- Where a note opens for writing:
    -- split | float | toggle | current | tab
    editor = { style = "split", position = "right", size = 60 },
}
```
<!-- /gen:config -->

Three display knobs, because they answer three questions: how you know a note
exists, how you glance at it, and where you write it. A transient float for
previewing and a persistent right split for editing is a normal combination
that one setting cannot express.

Signs span every line of a multi-line note, and when notes overlap the worst
anchor status wins the gutter. A healthy todo signs as `☐`, checked off to
`☑` once it is no longer open; notes keep the `▍` stripe, and every hurt
status keeps its own glyph — hurt is louder than kind. A healthy note with
no prose yet shows a dimmed sign — a bare anchor is a deletion candidate,
and looks like one.
The `summary` style goes further and puts prose line one at the end of the
line, in the note's own pen: margin notes you read without asking.

`:Sidenote highlight` additionally marks the annotated text itself — ink
over the words, a range by its exact columns — per buffer, the way
`:set spell!` toggles: `on` flips the default, `always` and `never` pin it.
Capturing while a toggle has them hidden reveals them again, so a fresh
mark never looks like a failed capture. By default the ink is the
`SidenoteMark*` groups, one per anchor status, yours to restyle.

<!-- vimdoc:tag sidenote-pens -->

### Pens

A note can carry a pen, coloring its ink like a highlighter. Four come
seeded — `yellow`, `coral`, `blue` and `green`, background washes in the
`SidenotePen*` groups — and adding your own is one config entry naming the
highlight group its ink should use:

```lua
vim.g.sidenote = {
    pens = { pink = "MyPinkWash" },
}
```

Custom entries merge over the seeded ones. Pick a pen up in the browser: `t`
and `T` on its column cycle through `-` (none) and every configured pen, or
type the name and `:w`. A penless note keeps the status ink; anchor health
stays on the sign either way, so a drifted note is visible whatever color it
wears.

New notes are inked with the **active pen**. It starts as `pen` in your
config — unset starts penless — and `:Sidenote pen` changes it for the
session: bare, it offers the ring; with a name (`:Sidenote pen coral`,
`:Sidenote pen none`) it sets directly. `<Plug>(SidenotePen)` rotates
through `none` and every configured pen.

<!-- vimdoc:tag sidenote-statusline -->

#### The pen in your statusline

Live state is mirrored into `vim.g.sidenote_state`, a read-only table your
statusline can consume without calling Lua:

```vim
set statusline+=%{get(get(g:,'sidenote_state',{}),'pen','')}
```

For a chip drawn in the pen's own ink, use the component:

```lua
vim.o.statusline = vim.o.statusline
    .. "%{%v:lua.require'sidenote'.statusline()%}"
```

Config is input and state is output: `vim.g.sidenote.pen` is what a session
starts with, `vim.g.sidenote_state.pen` is where it is now. The plugin
never writes the former, and yours never needs to write the latter.

A `template` function seeds the buffer a new note opens into:

```lua
vim.g.sidenote = {
    template = function(ctx)
        return { "* TODO " .. ctx.path, "" }
    end,
}
```

The seed is an unsaved edit — the prose file stays empty until you write the
buffer yourself. `ctx` carries `path`, `filetype`, `scope`, `line_start`,
`line_end` and `text`.

<!-- vimdoc:tag sidenote-context-header -->

### The note editor

A note opens under its identity, pinned in the window's winbar on a
statusline-like background: location, kind and state, plus a swatch drawn
in the note's actual ink — the pen's wash, or a squiggle when the indicator
style is `underline`. Beneath it, a quoted snippet of the annotated code
*as it reads right now*, each line behind its own source line number and a
`│`, closed with a divider so the quote never blends into your prose. An
anchor short of exact shows its status and confidence in the status color,
keeping the originally captured line on a `was:` row — the one place you
write about code also tells you honestly where that code stands.

The header stays true while you work: editing the annotated code re-draws
the quote, and a change made in the browser shows through on return. A
note buffer also knows what it is — `b:sidenote` carries its id and
source — so browsing from inside a note lists the *annotated file's*
notes, never the store directory, and the note the editor moves away from
is saved on its way out.

<!-- vimdoc:tag sidenote-follow -->

### Follow

`:Sidenote follow` pins that window and keeps it pointed at the note under
your cursor. Crossing into another annotation re-points it — never focusing
it — and prose you edited is saved the moment the panel moves on, so the
store never lies to a reader outside the editor. Over unannotated code the
panel holds the last note rather than blanking; the context header is what
keeps a held-over note legible as such. Closing the panel turns following
off.

<!-- vimdoc:tag sidenote-menu -->

### Changing a note where you stand

`<Plug>(SidenoteMenu)` pops a small menu over the note under the cursor:
every kind, state and pen it could take with the current ones marked, plus
open, view and delete. Pick with `j`/`k` and `<CR>`, with the single keys
the action rows name, or with the mouse. Picking a value writes it at once
and keeps the menu up, so kind, state and pen can all be set in one visit;
deleting confirms first, quoting the prose it would destroy.

For single keystrokes instead, the cycle plugs rotate one field of the
note under the cursor, org-style: `(SidenoteCycleKind)`,
`(SidenoteCycleState)` and `(SidenoteCyclePen)`, the latter two with
`…Back)` variants.

<!-- vimdoc:tag sidenote-storage -->

### Where notes are stored

`strategy` is a string, a function, or a list tried in order:

| strategy | resolves to | fails when |
|---|---|---|
| `project` | `<root>/.sidenote/` | no project root is found |
| `global` | `<global_dir>/<key>/` | never |
| a function | whatever `fun(path)` returns | it returns `nil` |

Each entry is strict on its own terms. `project` errors rather than quietly
falling back, because silent fallback is wrong when you meant to commit your
notes. Write the fallback you want in the list.

The list is also the read order. Reads union every store in it, earlier entries
winning; writes go to the first that resolves.

A project root is `.sidenote/` itself, then `.git` / `.jj` / `.hg`, then
`Cargo.toml` / `package.json` / `go.mod` / `pyproject.toml` / `*.rockspec`. The
first is what makes `mkdir .sidenote` enough, with no repo and no config.

In-repo notes are committed by default. The plugin writes files and nothing
else.

<!-- vimdoc:tag sidenote-sidecar -->

### What a note is on disk

Two files:

```
01J9F3K2X7Q4V8M2ZC5T0BQWE.org             your prose
01J9F3K2X7Q4V8M2ZC5T0BQWE.metadata.json   our record
```

The plugin never opens the prose file for writing except when you edit it in
the browser and confirm. The extension is the entire format decision; metadata
is always JSON.

Every record carries its own project key and a project-relative path, so moving
a store from global to in-repo is a `mv`.

<!-- vimdoc:tag sidenote-browser -->

## The browser

An editable listing, in the spirit of oil.nvim:

```
▍ note  open      yellow  lua/lobby.lua:42-57    race in lobby join
▍ todo  open      -       lua/lobby.lua:88       move onto the new API
! note  wontfix   -       lua/lobby.lua          the old retry loop
```

Every column is yours to edit. Anchor status is the one thing the machine
owns, and it lives in the gutter — silently while a note is healthy, as a
status glyph the moment one is not.

Each note is a real fold, so `za`, `zR`, `zM` and your own fold mappings work.
A closed row previews the summary beside the note's columns; expanding it
reveals the prose itself, verbatim at the margin beneath the header with the
summary as its first line, editable in place and copyable exactly as stored.

On `:w`:

| edit | result |
|---|---|
| any prose line, including the summary | rewrites that note |
| `kind`, `state` or the pen | updates the record |
| the position in the location | re-scopes, re-anchored |
| the path in the location | moves it, re-anchored |
| deleting a row | deletes the note |

`dd` on a collapsed row deletes the whole note, prose and all. A vim operator
applies to an entire closed fold, so that comes free.

Only `:w` applies anything, and closing an edited listing simply discards:
the listing is a projection of the store, not a document, so vim never asks
you to save it.

Nothing applies until you confirm, and anything lossy is listed apart:

```
sidenote: apply 5 changes?

  WRITE    2 notes' prose
  CHANGE   kind   note -> todo
  MOVE     lua/lobby.lua:88 -> lua/net.lua:31   (re-anchored by content)

  ── these lose information ──
  RESCOPE  lua/lobby.lua:42-57 -> lua/lobby.lua   (DROPS ANCHOR)
  DELETE   1 annotation   (REMOVES PROSE FILE)
```

`-` widens to every annotation in the project, sorted by path then line. `a`
creates a file-wide note — on the listed file, or in a project listing on
whichever file you name, suggesting the row under the cursor — and opens it
for writing.

<!-- vimdoc:tag sidenote-filtering -->

### Filtering

Either listing narrows by `kind`, `state`, anchor `status`, or a `path`
substring. Filters combine, and re-filtering narrows the listing you have
rather than opening another. `-` carries the filter with it. Inside a listing
the `f` keys ask interactively — `fk`, `fs`, `fa`, `ff` — and `fc` widens all
the way back out.

A filtered-out row is absent, not hidden. Saving a filtered listing cannot
touch an annotation it did not show you.

Cleanup is `:Sidenote project status=orphaned`, then `VGd` and `:w`.

<!-- vimdoc:tag sidenote-api -->

## Lua API

<!-- gen:api -->
`sidenote.add({opts})`

Annotate the current buffer and open the new note for writing.

`sidenote.refresh({bufnr})`

Re-resolve and repaint a buffer's annotations.

`sidenote.entries({bufnr})`

Every annotation targeting a buffer, resolved against its current text.

`sidenote.at_cursor({entries})`

Annotation the cursor is in: the narrowest holding it, else a file-wide one.

`sidenote.browse({opts})`

Open the editable listing of this file's annotations.

`sidenote.browse_project({opts})`

Open the editable listing of every annotation in the project.

`sidenote.view()`

Glance at the annotation under the cursor without leaving the code.

`sidenote.open()`

Open the annotation under the cursor for writing.

`sidenote.next()`

Jump to the next annotation and preview it.

`sidenote.prev()`

Jump to the previous annotation and preview it.

`sidenote.toggle_highlight()`

Toggle this buffer's range highlights, the way spell is toggled.

`sidenote.pen()`

The active pen's name, or nil when new notes start penless.

`sidenote.statusline()`

A statusline component: the active pen as a chip in its own ink, or "".

`sidenote.follow()`

Toggle the note editor following the cursor from note to note.

<!-- /gen:api -->

<!-- vimdoc:tag sidenote-agents -->

## For agents

The store is plain files, so `rg` over `*.metadata.json` and the prose files is
a supported interface. There is also a headless resolver:

```bash
nvim --headless -l cli/sidenote.lua export /path/to/proj
nvim --headless -l cli/sidenote.lua list /path/to/proj
nvim --headless -l cli/sidenote.lua list /path/to/proj --status orphaned
```

`export` prints JSON on stdout. `list` prints one tab-separated line per
annotation: location, status, kind, state, summary.

There is a ready-made agent skill in
[skills/sidenote/SKILL.md](skills/sidenote/SKILL.md) covering all of this —
how to read a store, what the gate means, and what an agent must never touch.
Copy or symlink it into `~/.claude/skills/` (or your agent's equivalent).

<!-- vimdoc:tag sidenote-export-gate -->

### The export gate

An annotation whose code no longer exists is never given a line number.

`attached` and `drifted` export with a position and a confidence. `ambiguous`,
`orphaned` and `filegone` export with `code_no_longer_exists: true`, no
`line_start`, and their original `anchor_text`, so an agent can search for what
the note was written against instead of being pointed at whatever now sits on
that line.

A naive single-line fuzzy matcher measured 8% precision against ground truth:
51 firings for 4 correct placements. A guess presented as a location sends an
agent to edit code that was never the subject.

```json
{
  "id": "01J9F3K2X7Q4V8M2ZC5T0BQWE",
  "kind": "todo",
  "state": "open",
  "path": "lua/lobby.lua",
  "status": "attached",
  "confidence": 1,
  "code_no_longer_exists": false,
  "line_start": 42,
  "line_end": 57,
  "anchor_text": "function M.join_lobby(id)",
  "prose": "race in lobby join"
}
```

`code_no_longer_exists` is always present, so branching on it needs no nil
check. `line_start` is the field that disappears.

Agents read. Humans write. Nothing here creates or resolves an annotation.

## Anchoring

A note records the bytes it was attached to, the lines around it, and several
hashes. Finding it again runs a ladder, first unique win taking it:

| tier | test | outcome |
|---|---|---|
| L0 | the whole file is unchanged | placed at the stored lines |
| L1 | the bytes at those lines still match | `attached` |
| L2 | the text appears exactly once | `attached` |
| L3 | several matches, context decides | `attached`, or `ambiguous` |
| L4 | matches once ignoring whitespace | `attached`, reformatted |
| L6 | scored fuzzy match >= 0.80 | `drifted`, with a confidence |
| | below 0.60, or nothing found | `orphaned` |
| | the file itself is gone | `filegone` |

The statuses, in worsening order:

<!-- gen:statuses -->
```
attached | drifted | ambiguous | orphaned | filegone
```
<!-- /gen:statuses -->

There is no L5: the number was reserved for a treesitter tier that was cut
before it was built.

Two thresholds rather than one, because a low-confidence guess presented as
truth rates worse with users than an honest orphan.

The 0.80 and 0.60 thresholds are measured. `harness/` samples real repository
history and grades placements against `git blame --reverse`, with the results
checked in.

Project-wide scans — the CLI, the project browser, `export` — cache their
resolutions under `cache_dir`, keyed by file content and record together, so
repeating one is cheap. The cache never lives inside a store, and deleting it
costs a rescan and nothing else.

<!-- vimdoc:tag sidenote-live-tracking -->

### While you edit

In an open buffer the ladder runs when the file is read and again after each
save. Between the two, the marks it placed track your edits directly: typing
inside a span grows it, deleting inside shrinks it, and edits above move it,
exactly as the text moves. Saving writes that back — the record re-baselines
to the span the mark tracked, so the note follows the content wherever your
editing took it.

Two things never re-baseline. A mark placed on a guess — a drifted note —
stays a guess, so editing near it cannot launder the placement into truth.
And typing over or deleting a whole span collapses its mark, sending the
ladder back to the stored text to decide — which is what lets a line cut
here be found again at the place you pasted it.

<!-- vimdoc:tag sidenote-never-deleted -->

### Nothing is ever auto-deleted

Losing the anchor changes a note's status, never its existence. Orphaning only
adds fields. Deletion is always something you asked for.

<!-- vimdoc:tag sidenote-limitations -->

## Limitations

Stated as contract rather than left to be discovered:

- Annotations live outside undo. `u` restores your code, never a deleted
  note — but the store is plain files, so commit it and recovery is your
  VCS's.
- Saving re-baselines an attached note to the span its mark tracked, so a
  save also asserts where your notes now live. Typing over a whole span
  breaks that assertion on purpose, and the resolver decides instead.
- The browser's concealed ids need `:syntax on`; without it every row
  shows its raw ULID.
- On macOS, `/tmp` and `/var` resolve into `/private`. Stored paths use the
  resolved form, so outside tooling comparing paths should realpath first.

## Health

`:checkhealth sidenote` reports configuration validity, whether the global
store is writable, the project store it found, and which optional tools are
present.

## License

[MIT](LICENSE).
