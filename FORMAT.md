# ditz file format

ditz issues are plain-text YAML files. The format is the interface: you can
`cat`, `grep`, `jq` (via `--json`), and hand-edit issues without the CLI. This
document is the reference for that format and the git model behind it.

## One issue = one file

Each issue is a file `.ditz/issue-<id>.yaml`. The project lives in
`.ditz/project.yaml`. Nothing is derived-and-stored — counts, ordering, and
"blocked" status are computed at read time, never cached in the files.

## Where the files live (git model)

The `.ditz/` directory is **not** in your working tree on a feature branch. It
lives on a dedicated orphan branch, `ditz-metadata`, so issue churn never
collides with code diffs. The CLI accesses it through a persistent sparse
worktree at `<repo>/.ditz-worktree` (reused across commands; set
`DITZ_EPHEMERAL_WORKTREE=1` for a throwaway worktree per command instead).

- Every write commits to `ditz-metadata` automatically.
- `ditz sync` fetches, merges, and pushes that branch. Merges auto-resolve:
  log_events union, status+disposition by last-write-wins, reference lists by
  three-way merge (no resurrection of deleted edges). Only when both sides
  change the same *identity* scalar (title, desc, type, component) does it
  abort and leave `.ditz-conflict/<file>.{LOCAL,REMOTE}`.
- A fresh clone joins automatically: the local `ditz-metadata` branch is
  created from `origin/ditz-metadata` on first read/write.

## Issue schema

```yaml
id: a3f29c…            # opaque, immutable, write-once. SHA1 by default;
                       # `--id <name>` sets a custom one. A unique prefix
                       # resolves it on the CLI, like a git hash.
title: Fix the widget
desc: |-               # free text, may be multi-line
  Longer description.
type: bugfix           # bugfix | feature | task
component: default     # single grouping axis; filter with `list --component`
release:               # optional release name, or absent/null
reporter: Ada <ada@example.com>
status: unstarted      # unstarted | in_progress | paused | closed
disposition:           # only when closed: fixed | wontfix | reorg
creation_time: 2026-06-15T12:00:00-00:00   # RFC3339
references:            # free-form strings (e.g. file:line, URLs, gh-37)
- src/widget.ml:42
log_events:            # append-only history
- time: 2026-06-15T12:00:00-00:00
  who: Ada
  what: created
  comment: ""
blocks:                # ids this issue blocks
- b7c1…
blocked_by:            # ids that block this issue (authoritative for the graph)
- d90a…
file_refs:             # optional structured references
- path: src/widget.ml
  line: 42
  note: the bug is here
```

Enums are written as plain scalars (`status: closed`), so `grep "status: closed"`
works. The legacy variant-map form (`status:\n  Closed: []`) is still read and
is rewritten to scalar form on the next save.

## Dependencies and "epics"

The dependency graph is just the `blocks` / `blocked_by` lists. `blocked_by` is
authoritative (the CLI keeps both sides in sync; a hand-edit or merge may not).

- `ditz blocks <a> <b>` records that a blocks b. It refuses an edge that would
  create a cycle.
- An **epic** is not a field — it is an issue `blocked_by` its members. It stays
  out of `ditz ready` until they all close.
- `ditz deps <id>` renders the subtree; `ditz deps --check` validates the whole
  graph (cycles, dangling references, one-sided edges); `ditz deps --dot` emits
  Graphviz.

## What is intentionally NOT here

- **No priority field.** `ditz ready` ranks by how many open issues each
  candidate transitively unblocks, then by age — derived at read time.
- **No parent/epic field.** Grouping is `component`; sequencing is the graph.
- **No labels/assignee fields** (imported beads values are preserved in a
  log-event comment for audit, not as fields).
- **No daemon, no sqlite.** Files plus git, nothing else.

## Editing by hand

Because issues are plain YAML on the `ditz-metadata` branch, you can edit them
directly in the `.ditz-worktree` checkout (or via `git show ditz-metadata:…`).
Keep `id` immutable, keep `log_events` append-only, and run `ditz deps --check`
afterward to confirm you didn't introduce a dangling or one-sided edge.
