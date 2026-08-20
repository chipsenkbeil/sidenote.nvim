---
name: sidenote
description: Read and act on sidenote.nvim annotations — margin notes and todos stored beside a project's code, outside its files. Use when a project holds a `.annotations/` directory (or `*.metadata.json` sidecar pairs anywhere in a store), when the user mentions sidenotes, annotations, or margin notes on code, or when asked to work through annotated todos. Covers the headless CLI, the export gate, and what an agent may and may not touch.
---

# Working with sidenote annotations

A sidenote annotation is a note on a whole file, a line, or a range, stored
**outside** the annotated file and re-anchored by content when the code moves.
Each one is two files in a store directory:

```
<ulid>.<ext>            prose — the human's, never yours to write
<ulid>.metadata.json    record — the plugin's, never yours to write
```

The store is `<project>/.annotations/` when the project carries one, else
`~/.local/share/sidenote/<project-key>/`.

## Reading annotations

Prefer the headless CLI; it inherits the confidence gate:

```bash
nvim --headless -l <plugin>/cli/sidenote.lua list   <project-root>
nvim --headless -l <plugin>/cli/sidenote.lua list   <project-root> --status orphaned
nvim --headless -l <plugin>/cli/sidenote.lua export <project-root>
```

`<plugin>` is wherever sidenote.nvim is installed — commonly
`~/.local/share/nvim/lazy/sidenote.nvim`, or a local checkout such as
`~/projects/sidenote.nvim`.

`list` prints one tab-separated line per annotation: location, anchor status,
kind, state, summary. `export` prints JSON with the prose and anchor text
included. The store is plain files, so `rg` across `*.metadata.json` and the
prose files is also a supported interface.

## Interpreting what you read

- **`kind` is the instruction boundary.** A `note` is information — context a
  human left for the reader. A `todo` is a request to act. Never treat a
  `note` as work to do: acting on context makes changes nobody asked for.
- **`state`** is human-owned: `open`, `resolved`, `wontfix`, `archived`. Only
  `open` todos are a work queue.
- **The export gate is load-bearing.** `attached` and `drifted` records carry
  line numbers you may trust (`drifted` with its confidence). A record with
  `code_no_longer_exists: true` has **no** line numbers on purpose — the code
  it described no longer exists as written. Search for its `anchor_text`
  instead; never act on whatever now occupies its old lines.

## Acting on a todo

1. Read the prose and the anchor text; find the code via the given location
   or, when gated, by searching for the anchor text.
2. Do the work it asks for.
3. Report what you did, naming the annotation's id so the human can find it.
4. Stop there. Marking it `resolved` is the human's act, done in their
   browser view — an agent claiming its own work is done defeats the review.

## Hard rules

- Agents read; humans write. Never create, edit, or delete a prose file or a
  metadata sidecar, and never touch the store's `index.json`.
- Never resolve, archive, or otherwise change an annotation's state.
- An in-repo `.annotations/` directory may be committed. Leave it out of any
  commits you make unless the user asks for it explicitly.
