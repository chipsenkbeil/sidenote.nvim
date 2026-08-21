---
name: sidenote
description: Read and act on sidenote.nvim annotations — margin notes and todos stored beside a project's code, outside its files. Use when a project holds a `.sidenote/` directory (or `*.metadata.json` sidecar pairs anywhere in a store), when the user mentions sidenotes, annotations, or margin notes on code, or when asked to work through annotated todos. Covers the headless CLI, the export gate, and what an agent may and may not touch.
---

# Working with sidenote annotations

A sidenote annotation is a note on a whole file, a line, or a range, stored
**outside** the annotated file and re-anchored by content when the code moves.
Each one is two files in a store directory:

```
<ulid>.<ext>            prose — the human's; you may append, never rewrite
<ulid>.metadata.json    record — the plugin's; `state` is the one field you flip
```

The store is `<project>/.sidenote/` when the project carries one, else
`~/.local/share/sidenote/<project-key>/`.

## Reading annotations

Prefer the headless CLI; it inherits the confidence gate:

```bash
nvim --headless -l <plugin>/cli/sidenote.lua list   <project-root>
nvim --headless -l <plugin>/cli/sidenote.lua list   <project-root> --status orphaned
nvim --headless -l <plugin>/cli/sidenote.lua list   <project-root> --change <prefix>
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
- **`state`** — `open`, `resolved`, `wontfix`, `archived`. Only `open`
  todos are a work queue, and the only state change you ever make is the
  final act of addressing one (below).
- **The export gate is load-bearing.** `attached` and `drifted` records carry
  line numbers you may trust (`drifted` with its confidence). A record with
  `code_no_longer_exists: true` has **no** line numbers on purpose — the code
  it described no longer exists as written. Search for its `anchor_text`
  instead; never act on whatever now occupies its old lines.

## Reviewing a change

When the user reviews a change (jj) offline, their review comments are
`open` todos stamped with that change's id — the `change` field in
`export` output, filterable with `list --change <prefix>`. Asked to
address a review, work only that filtered queue and resolve each todo the
standard way below; notes stamped with other changes, or with none, are
not part of the review. In plain git the stamp is a commit sha instead —
the `commit` field, filterable with `list --commit <prefix>`.

## Acting on a todo

The model is a GitHub review thread: do the work, reply on the thread, then
resolve it — so the human reviews *how* it was resolved instead of hunting
for whether anything happened.

1. Read the prose and the anchor text; find the code via the given location
   or, when gated, by searching for the anchor text.
2. Do the work it asks for.
3. Append your response to the prose file — beneath the human's text, never
   touching it — as a blank line, a divider, and a signed, dated account:

   ```
   ---
   agent (2026-08-20): Extracted the retry loop into net/backoff.lua and
   pointed both call sites at it. All 214 tests pass.
   ```

4. Flip `"state"` in the metadata sidecar to `"resolved"` — that one field,
   the rest byte-for-byte untouched. Use `"wontfix"` when you determined
   the request should not be done, and say why in your appended response.
5. Report what you did, naming the annotation's id.

## Hard rules

- Never rewrite or delete a human's prose; your only write there is an
  appended response at the end of the file.
- The only metadata field you may change is `state`, and only as the final
  act of a todo you actually addressed — never to triage, tidy, or silence.
- A `note` is context: no prose appends, no state changes, no action.
- Never create or delete annotations, and never write into the plugin's
  resolution cache.
- An in-repo `.sidenote/` directory may be committed. Leave it out of any
  commits you make unless the user asks for it explicitly.
