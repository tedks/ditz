(** Byte-exact historical generated snippets. Keep these immutable: refresh
    must never mistake a user edit for an old generated block. Source commits
    identify the first occurrence of each distinct snippet, including versions
    used before merge. See docs/onboarding.md. *)

let snippets = [
  (* ea1e1d3:ocaml/lib/onboarding.ml *)
  {ditz|## Issue tracking with ditz

This project uses `ditz` (not beads). Issues are plain-text YAML on the
`ditz-metadata` git branch; the `ditz` CLI reads and writes them.

The loop:
- `ditz ready` — what to work on now (unblocked, ranked by how much each unblocks)
- `ditz start <id>` — mark in progress
- `ditz close <id> --reason "..."` — close with why (or `--wontfix` / `--reorg`)
- `ditz reopen <id>` — revive a closed issue

Create / inspect:
- `ditz add "title" -t bug|feature|task -c <component> --desc "..."`
- `ditz show <id>` · `ditz list --status open` · `ditz search <q>`
- `--json` on any command for machine output; `--ids-only` for just ids
- ids: copy them from output; a unique prefix works (like git hashes);
  `--id <name>` sets a deterministic id (re-creating with it is idempotent)

Structure (there are no priority / epic / parent fields — urgency is derived,
hierarchy is expressed in the graph):
- grouping: `-c <component>` + `ditz list --component <c>`
- sequencing: `ditz blocks <a> <b>` (a blocks b); an "epic" is just an issue
  blocked by its members — it stays out of `ready` until they close
- `ditz deps <id>` shows the dependency tree; `ditz deps --check` validates it

Sync: `ditz sync` fetches/merges/pushes the metadata branch. See FORMAT.md for
the file format and git model.
|ditz};
  (* d0eaaf7:ocaml/lib/onboarding.ml *)
  {ditz|## Issue tracking with ditz

This project uses `ditz` (not beads). Issues are plain-text YAML on the
`ditz-metadata` git branch; the `ditz` CLI reads and writes them.

The loop:
- `ditz ready` — what to work on now (unblocked, ranked by how much each unblocks)
- `ditz start <id>` — mark in progress
- `ditz close <id> --reason "..."` — close with why (or `--wontfix` / `--reorg`)
- `ditz reopen <id>` — revive a closed issue

Create / inspect:
- `ditz add "title" -t bugfix|feature|task -c <component> --desc "..."`
- `ditz show <id>` · `ditz list --status unstarted|in_progress|paused|closed` · `ditz search <q>`
- `--json` on any command for machine output; `--ids-only` for just ids
- ids: copy them from output; a unique prefix works (like git hashes);
  `--id <name>` sets a deterministic id (re-creating with it is idempotent)

Structure (there are no priority / epic / parent fields — urgency is derived,
hierarchy is expressed in the graph):
- grouping: `-c <component>` + `ditz list --component <c>`
- sequencing: `ditz blocks <a> <b>` (a blocks b); an "epic" is just an issue
  blocked by its members — it stays out of `ready` until they close
- `ditz deps <id>` shows the dependency tree; `ditz deps --check` validates it

Sync: `ditz sync` fetches/merges/pushes the metadata branch. See FORMAT.md for
the file format and git model.
|ditz};
  (* cdd5d69:lib/onboarding.ml *)
  {ditz|## Issue tracking with ditz

This project uses `ditz` (not beads). Issues are plain-text YAML on the
`ditz-metadata` git branch; the `ditz` CLI reads and writes them.

The loop:
- `ditz ready` — what to work on now (unblocked, ranked by how much each unblocks)
- `ditz start <id>` — mark in progress
- `ditz close <id> --reason "..."` — close with why (or `--wontfix` / `--reorg`)
- `ditz reopen <id>` — revive a closed issue

Create / inspect:
- `ditz add "title" -t bugfix|feature|task -c <component> --desc "..."`
- `ditz show <id>` · `ditz list --status unstarted|in_progress|paused|closed` · `ditz search <q>`
- `--json` on any command for machine output; `--ids-only` for just ids

Naming issues: there is no separate name field — `--id` IS the name.
- `ditz add "title" --id <name>` makes `<name>` the permanent id (letters,
  digits, `-`, `_`); without `--id` you get a SHA1. Any unique prefix of an id
  works on the CLI, and an exact id always wins.
- Re-running `add --id <name>` for an existing issue changes NOTHING (safe to
  retry, but not an update). Edit with `ditz set <id> --title/--desc/-t/-c`.

Structure (there are no priority / epic / parent fields — urgency is derived,
hierarchy is expressed in the graph):
- grouping: `-c <component>` + `ditz list --component <c>`
- sequencing: `ditz blocks <a> <b>` (a blocks b); an "epic" is just an issue
  blocked by its members — it stays out of `ready` until they close
- `ditz deps <id>` shows the dependency tree; `ditz deps --check` validates it

Sync: `ditz sync` fetches/merges/pushes the metadata branch. See FORMAT.md for
the file format and git model.
|ditz};
  (* 3867001:lib/onboarding.ml *)
  {ditz|## Issue tracking with ditz

This project uses `ditz` (not beads). Issues are plain-text YAML on the
`ditz-metadata` git branch; the `ditz` CLI reads and writes them.

The loop:
- `ditz ready` — what to work on now (unblocked, ranked by how much each unblocks)
- `ditz start <id>` — mark in progress
- `ditz close <id> --reason "..."` — close with why (or `--wontfix` / `--reorg`)
- `ditz reopen <id>` — revive a closed issue

Create / inspect:
- `ditz add "title" -t bugfix|feature|task -c <component> --desc "..."`
- `ditz show <id>` · `ditz list --status unstarted|in_progress|paused|closed` · `ditz search <q>`
- `--json` on any command for machine output; `--ids-only` for just ids

Naming issues: there is no separate name field — `--id` IS the name.
- `ditz add "title" --id <name>` makes `<name>` the permanent id (ASCII
  letters, digits, `-`, `_`); without `--id` you get a SHA1. Commands that take
  an id accept any unique prefix, and an exact id always wins.
- Re-running `add --id <name>` for an existing issue changes NOTHING (safe to
  retry, but not an update). Edit with e.g. `ditz set <id> --title "..."`
  (also `--desc`, `-t`, `-c`).

Structure (there are no priority / epic / parent fields — urgency is derived,
hierarchy is expressed in the graph):
- grouping: `-c <component>` + `ditz list --component <c>`
- sequencing: `ditz blocks <a> <b>` (a blocks b); an "epic" is just an issue
  blocked by its members — it stays out of `ready` until they close
- `ditz deps <id>` shows the dependency tree; `ditz deps --check` validates it

Sync: `ditz sync` fetches/merges/pushes the metadata branch. See FORMAT.md for
the file format and git model.
|ditz};
  (* 2439961:lib/onboarding.ml *)
  {ditz|## Issue tracking with ditz

This project uses `ditz` (not beads). Issues are plain-text YAML on the
`ditz-metadata` git branch; the `ditz` CLI reads and writes them.

The loop:
- `ditz ready` — what to work on now (unblocked, ranked by how much each unblocks)
- `ditz start <id>` — mark in progress
- `ditz close <id> --reason "..."` — close with why (or `--wontfix` / `--reorg`)
- `ditz reopen <id>` — revive a closed issue

Create / inspect:
- `ditz add "title" -t bugfix|feature|task -c <component> --desc "..."`
- `ditz show <id>` · `ditz list --status unstarted|in_progress|paused|closed` · `ditz search <q>`
- `--json` on any command for machine output; `--ids-only` for just ids

Naming issues: there is no separate name field — `--id` IS the name.
- `ditz add "title" --id <name>` makes `<name>` the permanent id (ASCII
  letters, digits, `-`, `_`); without `--id` you get a SHA1. Other commands
  that take an id accept any unique prefix (an exact id always wins);
  `add --id` itself matches exactly.
- Re-running `add --id <name>` for an existing issue changes NOTHING (safe to
  retry, but not an update). Edit with e.g. `ditz set <id> --title "..."`
  (also `--desc`, `-t`, `-c`).

Structure (there are no priority / epic / parent fields — urgency is derived,
hierarchy is expressed in the graph):
- grouping: `-c <component>` + `ditz list --component <c>`
- sequencing: `ditz blocks <a> <b>` (a blocks b); an "epic" is just an issue
  blocked by its members — it stays out of `ready` until they close
- `ditz deps <id>` shows the dependency tree; `ditz deps --check` validates it

Sync: `ditz sync` fetches/merges/pushes the metadata branch. See FORMAT.md for
the file format and git model.
|ditz};
  (* fd0ac13:lib/onboarding.ml *)
  {ditz|## Issue tracking with ditz

This project uses `ditz` (not beads). Issues are plain-text YAML on the
`ditz-metadata` git branch; the `ditz` CLI reads and writes them.

The loop:
- `ditz ready` — what to work on now (unblocked, ranked by how much each unblocks)
- `ditz start <id>` — mark in progress
- `ditz close <id> --reason "..."` — close with why (or `--wontfix` / `--reorg`)
- `ditz reopen <id>` — revive a closed issue

Create / inspect:
- `ditz add "title" -t bugfix|feature|task -c <component> --desc "..."`
- `ditz show <id>` · `ditz list --status open|unstarted|in_progress|paused|closed` (comma-separate to combine) · `ditz search <q>`
- `--json` on any command for machine output; `--ids-only` for just ids

Naming issues: there is no separate name field — `--id` IS the name.
- `ditz add "title" --id <name>` makes `<name>` the permanent id (ASCII
  letters, digits, `-`, `_`); without `--id` you get a SHA1. Other commands
  that take an id accept any unique prefix (an exact id always wins);
  `add --id` itself matches exactly.
- Re-running `add --id <name>` for an existing issue changes NOTHING (safe to
  retry, but not an update). Edit with e.g. `ditz set <id> --title "..."`
  (also `--desc`, `-t`, `-c`).

Structure (there are no priority / epic / parent fields — urgency is derived,
hierarchy is expressed in the graph):
- grouping: `-c <component>` + `ditz list --component <c>`
- sequencing: `ditz blocks <a> <b>` (a blocks b); an "epic" is just an issue
  blocked by its members — it stays out of `ready` until they close
- `ditz deps <id>` shows the dependency tree; `ditz deps --check` validates it

Sync: `ditz sync` fetches/merges/pushes the metadata branch. See FORMAT.md for
the file format and git model.
|ditz};
]
