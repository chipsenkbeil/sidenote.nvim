# sidenote.nvim

Annotate source code with notes stored **outside** the annotated file. A note
attaches to a whole file, a line, or a range, and survives the code it points at
being edited, moved, reformatted, or deleted.

Two uses, both intended: durable personal margin notes, and a work queue an AI
agent can read and act on.

## Why the notes live outside the file

Because a comment changes the code and a note does not. You can annotate a
vendored dependency, a file you have no business editing, or a function you are
still deciding about, and nothing you write ends up in a diff.

The cost of that is anchoring — a note has to find its code again after the code
moves. That is the part of this plugin with actual engineering in it; see
[Anchoring](#anchoring).

## Requirements

Neovim **0.11 or newer** — that is where `vim.fs.relpath` arrived, which the
store uses to keep every record's path project-relative. CI runs the suite
against each 0.11 point release and nightly.

**No dependencies.** Some things are better if you have them, and none are
required:

| optional | buys |
|---|---|
| nvim-orgmode | org editing of notes, because the prose file ends in `.org` |
| treesitter | symbol capture, and a structural resolution tier |
| git / jj | provenance stamping, never used for resolution |

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "chipsenkbeil/sidenote.nvim" }
```

There is **no `setup()` to call.** Configuration is `vim.g.sidenote`, and every
field has a default.

## Getting started

```vim
" Annotate the current line, or the selection in visual mode
nmap <Leader>na <Plug>(SidenoteAdd)
xmap <Leader>na <Plug>(SidenoteAdd)

" Glance at the note under the cursor, or open it for writing
nmap <Leader>nv <Plug>(SidenoteView)
nmap <Leader>no <Plug>(SidenoteOpen)

" The editable listing of this file's notes, and of the whole project's
nmap <Leader>nb <Plug>(SidenoteBrowse)
nmap <Leader>nB <Plug>(SidenoteBrowseProject)
```

Annotate a line, write your note, save. A sign appears in the gutter. Edit the
code around it, reformat it, move it down the file — the sign follows.

## Configuration

Defaults shown:

```lua
vim.g.sidenote = {
    -- Extension and filetype of prose files
    filetype = "txt",

    -- Where notes are stored, tried in order
    strategy = { "project", "global" },
    global_dir = vim.fn.stdpath("data") .. "/sidenote",
    project_dir = ".annotations",

    -- sign | virt_text | highlight | underline | none
    indicator = { style = "sign" },

    -- float | virt_lines | split | none
    preview = { style = "float", max_lines = 20 },

    -- split | float | toggle | current | tab
    editor = { style = "split", position = "right", size = 60 },
}
```

Three display knobs rather than one, because they are three questions:
**indicator** is how you know a note exists, **preview** is glancing at it
without leaving the code, **editor** is where you actually write. A cheap
transient float for previewing and a persistent right split for editing is a
normal combination that one setting cannot express.

### Where notes are stored

`strategy` is a string, a function, or a list tried in order:

| strategy | resolves to | fails when |
|---|---|---|
| `project` | `<root>/.annotations/` | no project root is found |
| `global` | `~/.local/share/nvim/sidenote/<key>/` | never |
| a function | whatever `fun(source_path)` returns | it returns `nil` |

Each entry is strict on its own terms — `project` errors rather than quietly
falling back, because silent fallback is exactly wrong when you meant to commit
your notes. Write the fallback you want in the list instead.

**The list is also the read order.** Reads union every store in it, earlier
entries winning; writes go to the first that resolves. So
`{ "project", "global" }` means "write to the project store when there is one,
and always show me both".

A project root is found by looking for, in order: `.annotations/` itself, then
`.git` / `.jj` / `.hg`, then `Cargo.toml` / `package.json` / `go.mod` /
`pyproject.toml` / `*.rockspec`. The first of those is what makes
`mkdir .annotations` enough to opt a plain directory in — no repo, no config,
nothing else on disk.

**In-repo notes are committed by default.** The plugin writes files and does
nothing else; if you want them ignored, that is your `.gitignore` to edit.

## What a note is on disk

Two files:

```
01J9F3K2X7Q4V8M2ZC5T0BQWE.org             your prose
01J9F3K2X7Q4V8M2ZC5T0BQWE.metadata.json   our record
```

The plugin never opens the prose file for writing except when you edit it in the
browser and confirm. Splitting them is what makes the format your choice: the
prose file's extension is the entire decision, and metadata is always JSON.

Every record carries its own `project_key` and a project-relative path, so
moving a store from global to in-repo is a `mv` rather than data loss.

## The browser

`<Plug>(SidenoteBrowse)` opens an editable listing of the current file's notes,
in the spirit of oil.nvim:

```
▍ note  open      lua/lobby.lua:42-57    race in lobby join
▍ todo  open      lua/lobby.lua:88       refactor onto the new API
! note  wontfix   lua/lobby.lua          the old retry loop
```

Every column is yours to edit. The gutter carries anchor status, which is the
one thing the machine owns.

Each note is a **real fold**, so `za`, `zR`, `zM` and your own fold mappings all
work. Expanding one reveals its prose, indented, which you can edit in place.

| what you do | what happens on `:w` |
|---|---|
| edit any prose line, including the summary | rewrites that note |
| change `kind` or `state` | updates the record |
| change the position in the location | re-scopes, re-anchored where you said |
| change the path in the location | moves it, re-anchored in the new file |
| type a new line with no id | creates a file-wide note |
| delete a row | deletes the note |

`dd` on a collapsed row deletes the whole note, prose and all — a vim operator
applies to an entire closed fold, so that comes free.

Nothing is applied until you confirm, and anything that loses information is
listed separately:

```
sidenote: apply 5 changes?

  WRITE    2 notes' prose
  CHANGE   1 annotation   kind   note -> todo
  MOVE     lua/lobby.lua:88 -> lua/net/lobby.lua:31  (re-anchored)

  ── these lose information ──
  RESCOPE  lua/lobby.lua:42-57 -> lua/lobby.lua       (DROPS ANCHOR)
  DELETE   1 annotation                               (REMOVES PROSE FILE)
```

`<CR>` opens the real prose file, which is where you get org (or markdown)
highlighting. `<Tab>` and `<S-Tab>` move between columns.

`-` widens to **every annotation in the project**, sorted by path then line. It
edits exactly the same way; a new row there creates a note on whichever file its
location names.

### Filtering

Either listing narrows by `kind`, `state`, or anchor `status`:

```vim
:Sidenote browse  --kind=todo
:Sidenote project --status=orphaned
:Sidenote project --kind=todo --state=open
```

Filters combine, and re-filtering narrows the listing you already have rather
than opening a second one. `-` carries the filter with it, so widening a view of
orphans shows the project's orphans.

**A filtered-out row is absent, not hidden.** Saving a filtered listing can
never touch an annotation it did not show you.

Deleting every orphaned row with `dd` and saving is the whole cleanup story:

```vim
:Sidenote project --status=orphaned
```

then `VGd` and `:w`.

## Commands

One command with subcommand completion:

```
:Sidenote add | browse | project | refresh | view | open | next | prev
```

`:Sidenote project [path]` opens the project-wide listing; without an argument
it uses the project containing the current file.

## For agents

The store is plain files, so `rg` over `*.metadata.json` and the prose files is
a supported interface. There is also a headless resolver:

```bash
# Every annotation, resolved, as JSON on stdout
nvim --headless -l cli/sidenote.lua export /path/to/project

# One greppable line each: location, status, kind, state, summary
nvim --headless -l cli/sidenote.lua list /path/to/project
nvim --headless -l cli/sidenote.lua list /path/to/proj --status orphaned
```

### The export gate, and why it exists

**An annotation whose code no longer exists is never given a line number.**

`attached` and `drifted` export with a resolved position and a `confidence` to
weigh it by. `ambiguous`, `orphaned` and `filegone` export with
`code_no_longer_exists: true`, **no** `line_start`, and their original
`anchor_text` — so an agent can see what the note was written against and search
for it, rather than be pointed at whatever happens to sit at that line now.

This is not caution for its own sake. A naive single-line fuzzy matcher measured
**8% precision** against ground truth on real repository history: 51 firings for
4 correct placements. A guess presented as a location sends an agent to edit
code that was never the subject of the note.

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
  "anchor_text": "function M.join_lobby(id)\n  local room = rooms[id]",
  "prose": "race in lobby join\n\nTwo clients can both win"
}
```

`code_no_longer_exists` is always present, so branching on it needs no nil
check. `line_start` is the field that disappears.

**Agents read; humans write.** Nothing here creates or resolves an annotation.

## Anchoring

A note records the bytes it was attached to, the lines above and below it, and
several hashes. Finding it again runs a ladder, first unique win taking it:

| tier | test | outcome |
|---|---|---|
| L0 | the whole file is unchanged | placed at the stored lines |
| L1 | the bytes at those lines still match | `attached` |
| L2 | the anchor text appears exactly once in the file | `attached` |
| L3 | several matches, disambiguated by surrounding context | `attached`, or `ambiguous` |
| L4 | matches once ignoring whitespace | `attached`, reformatted |
| L6 | scored fuzzy match ≥ 0.80 | `drifted`, with a confidence |
| — | below 0.60, or nothing found | `orphaned` |
| — | the file itself is gone | `filegone` |

Two thresholds rather than one, because a low-confidence guess presented as
truth rates worse with users than an honest orphan.

The 0.80 and 0.60 thresholds are **measured, not chosen**. `harness/` samples
real repository history and grades placements against `git blame --reverse`;
`harness/baseline.json` holds the results with the commits pinned.

**A note is never deleted by the plugin.** Losing the anchor changes a note's
status, never its existence, and orphaning only ever *adds* fields. Deletion is
always something you asked for.

## License

[MIT](LICENSE).
