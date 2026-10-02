# Agent recipes

These examples use the existing CLI from a shell in the intended, initialized
project. Check your working directory and `~/.ditz-config` before writing: a
configured issue directory can select a different store. See [FORMAT.md](../FORMAT.md)
for storage and ID rules. The IDs and text below are synthetic.

If your project requires Nix, run the script inside `nix develop --command sh
path/to/script.sh`. Capture each `ditz` command's output inside that script;
environment startup messages are not part of ditz's machine output.

## Discover commands and select issues

```sh
ditz --help=plain
ditz add --help=plain
ditz list --help=plain

ditz list --json
ditz list --type bugfix --component parser --status unstarted --json
```

`--help=plain` needs no pager. `list --json` returns an array of issues, including
closed issues unless filtered. The three filters combine: type (`bugfix`,
`feature`, `task`), component (an exact name), and status (`unstarted`,
`in_progress`, `paused`, `closed`). Use the documented values; older versions
warn about unknown type/status values but leave that filter unapplied.

## Create a named issue and capture its exact ID

```sh
set -eu
issue_id=$(ditz add 'Handle a missing widget' --id widget-missing \
  --type bugfix --component parser --desc-stdin --ids-only <<'DESCRIPTION'
A quote ('), a dollar sign ($), and `backticks` are literal text here.
The widget should remain absent until its input is available.
DESCRIPTION
)
[ "$issue_id" = widget-missing ]

ditz comment "$issue_id" --stdin <<'COMMENT'
Observed with synthetic input: $(echo example) is literal text.
Acceptance: no invented default value.
COMMENT
```

`--ids-only` returns the exact ID, so no list/grep lookup is needed. Keep and reuse
that ID. `add --id` creates once: if the ID already exists, it returns the existing
issue unchanged, ignoring the supplied creation fields. It is not an update;
use `ditz set "$issue_id" --desc-stdin` to replace the description. Inspect an
existing issue with `ditz show "$issue_id" --json` before assuming its fields match.

Quoting the here-document delimiter prevents shell expansion of quotes, dollars,
backticks and command substitutions in the body. Internal newlines survive, but
ditz trims whitespace from the beginning and end of stdin, including the final
newline. Re-adding an existing ID does not read stdin; prefer a here-document or
owned input file to an unbounded producer.

Creation with the same name can be retried; the whole script cannot be replayed
safely as a unit. Comments are append operations with no retry deduplication.
If a comment's result is lost, inspect the issue's `log_events` before deciding
whether to send it again.

## Read readiness, then record work status

```sh
ditz ready --json
ditz start widget-missing --json
```

Use an open issue selected from your current readiness result. `ready` lists
unstarted or paused issues with no open blockers. It is a snapshot; another worker
can select the same issue. `start` records `in_progress` and a history event, but provides no exclusive
claim, assignee or lease. Coordinate ownership outside these commands and inspect
`start`'s exit status and per-item `errors` before proceeding.

## Close several issues and handle partial success

Suppose `widget-missing` exists and `widget-unknown` does not. Preserve stdout
and the exit status even when a batch fails:

```sh
close_status=0
ditz close widget-missing widget-unknown --fixed --json \
  > close-result.json || close_status=$?
printf 'exit status: %s\n' "$close_status"
cat close-result.json
```

The exit status is 1 and the JSON has this shape:

```json
{"closed":["widget-missing"],"errors":[{"id":"widget-unknown","error":"No issue found matching 'widget-unknown'"}],"disposition":"fixed"}
```

Check both the process status and `errors`. Each `closed` entry is a successful
ID; each error contains the requested ID and a message. This is partial success,
not an all-or-nothing batch. With no per-item errors, the command exits 0.

Resolve the reported problem, then retry only the failed IDs. Do not replay the
successful IDs: closing an already closed issue appends another close event.
A save error or interrupted process needs inspection of current state and history
before retrying; do not infer that nothing changed. Configuration or argument
errors can instead produce stderr without this JSON object, so keep stderr and
do not assume every failure has a parseable result.
