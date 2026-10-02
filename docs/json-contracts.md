# JSON results and retries

This reference describes the current OCaml CLI, not a proposed uniform response
schema. Check the executable you will run with `command -v ditz` and
`ditz COMMAND --help=plain`; an older installed binary can differ from this
checkout. The [agent recipes](agent-recipes.md) show complete shell workflows.

## Capture the whole outcome

Keep stdout, stderr, and process status separately. A nonzero status can accompany
useful JSON and completed writes. Conversely, `--json` does not guarantee JSON on
every failure. For example, configuration, lookup, lock, and argument errors can
produce only stderr. Do not pipe through a command that hides ditz's exit status.

```sh
result_status=0
ditz close widget-a widget-b --fixed --json \
  > close-result.json 2> close-result.err || result_status=$?
printf 'exit status: %s\n' "$result_status"
cat close-result.json
cat close-result.err >&2
```

Use owned output paths. If Nix provides the project tools, run the containing
script with `nix develop --command sh path/to/script.sh`; capture the individual
ditz invocation inside it so environment startup output stays outside the JSON.

| Status | Meaning |
|---|---|
| `0` | The command's own success condition held. Check command-specific fields and stderr caveats below. |
| `1` | An operational or validation failure; a batch may have succeeded for some items. |
| `124` | Cmdliner rejected the invocation, such as an unknown option or missing argument; no result object is promised. |
| Other nonzero / signal / lost response | Unexpected failure or unknown outcome. Inspect current state before retrying a mutation. |

`--json` takes precedence over `--ids-only` where both are supported. The special
`deps --dot` mode takes precedence over `--json` and emits DOT, so do not combine
them when expecting JSON. `--ids-only` is useful for capturing a new issue ID;
it is not a JSON error protocol, and `-q` controls logging instead.

## Result shapes

`IssueSummary` below is exactly `{"id":string,"title":string,"status":string}`.
`Issue` is the fuller record described after the table. Arrays can be empty.
These are shapes, not literal JSON examples: `string`, `Issue[]`, and alternatives
describe values. Error messages are diagnostic text, not stable error codes.

| Command with `--json` | Result on its normal reporting path |
|---|---|
| `list`, `search TEXT`, `ready`, `context` | `Issue[]` |
| `show ID` | `Issue` |
| `add TITLE`, `set ID ...` | `IssueSummary` |
| `comment ID ...` | `{"id":string,"commented":true}` |
| `start ID...` | `{"started":IssueSummary[],"errors":[{"id":string,"error":string}]}` |
| `stop ID...` | `{"stopped":IssueSummary[],"errors":[{"id":string,"error":string}]}` |
| `reopen ID...` | `{"reopened":IssueSummary[],"errors":[{"id":string,"error":string}]}` |
| `close ID...` | `{"closed":string[],"errors":[{"id":string,"error":string}],"disposition":string}` |
| `drop ID` | `{"deleted":string}` |
| `blocks A B` | `{"blocker":string,"blocked":string}` |
| `unblocks A B` | `{"blocker":string,"blocked":string,"unblocked":true}` |
| `ref ID PATH[:LINE]` | `{"id":string,"ref":string}` |
| `assign ID RELEASE` | `{"id":string,"release":string}` |
| `unassign ID` | `{"id":string,"release":null}` |
| `deps ID` | `{"id":string,"blocks":string[],"blocked_by":string[],"transitively_blocks":string[]}` |
| `deps` or `deps --check` | `{"ok":boolean,"cyclic_components":string[][],"dangling":[{"issue":string,"missing":string,"relation":string}],"one_sided":[{"blocker":string,"blocked":string}]}` |
| `status` | `{"total":integer,"open":integer,"unstarted":integer,"in_progress":integer,"paused":integer,"closed":integer,"bugs":integer,"features":integer,"tasks":integer,"sync":SyncState}` |
| `sync` (including `--pull-only` / `--push-only`) | `{"pulled":integer,"pushed":integer,"head":string,"ahead":integer-or-null,"behind":integer-or-null}` |
| `init` | `{"project":string,"status":"initialized","onboarding":string}` |
| `onboard` | `{"path":string,"onboarding":string}` |
| `import FILE` | `{"created":string[],"skipped":string[],"warnings":string[],"notices":string[]}` |

`Issue` contains:

- Strings: `id`, `title`, `desc`, `type`, `component`, `reporter`, `status`,
  `creation_time` (RFC 3339).
- Nullable strings: `release`, `disposition`.
- String arrays: `references`, `blocks`, `blocked_by`.
- `log_events`: objects with string fields `time`, `who`, `what`, `comment`.
- `file_refs`: objects with `path` (string), `line` (integer or null), `note`
  (string or null).

Statuses are `unstarted`, `in_progress`, `paused`, `closed`; types are `bugfix`,
`feature`, `task`; dispositions are `fixed`, `wontfix`, `reorg`. `assign` means a
release assignment, not a person or agent assignment.

In `status`, the `bugs`, `features`, and `tasks` counts include only open issues;
they sum to `open`, not `total`.

`list` includes closed issues by default; `--status open` excludes them. `context`
without a focus returns open issues, but `context --issue ID` includes the focus
and its direct relations even if closed. `ready` is a snapshot of unstarted or
paused issues with no loaded open blockers, not a reservation of work.

Reads currently warn and skip unreadable issue files; a store-enumeration failure
can produce an empty result with a warning. Therefore an array, count, readiness
result, or clean graph check with exit `0` is not proof of a complete inventory.
Retain stderr and resolve read warnings before acting on absence or readiness.

`deps --check` exits `1` when `ok` is false. Each `cyclic_components` entry is a
set of mutually reachable IDs, not a path ordered around the cycle. `deps ID`
derives downstream `blocks` from the graph's `blocked_by` relationships, which
can differ from the stored reciprocal field when data is one-sided.

## Partial success and retries

The lifecycle commands (`start`, `stop`, `reopen`, `close`) process IDs one at a
time. Their success array contains resolved full IDs; each `errors[].id` is the
requested ID or prefix. They exit `1` if any per-item error occurred and `0`
otherwise. A batch is not an all-or-nothing transaction. Use exact captured IDs
for subsequent calls; a prefix can become ambiguous as the tracker grows.

For an existing `widget-a` and absent `widget-b`, closing both can return exit `1`
with this stdout:

```json
{"closed":["widget-a"],"errors":[{"id":"widget-b","error":"No issue found matching 'widget-b'"}],"disposition":"fixed"}
```

Do not replay `widget-a`. Resolve the failure for `widget-b`, inspect it if the
failure was a save error, and retry only the work still needed. A save error or
interruption must not be interpreted as a guarantee that no state changed.
Missing or unparsable JSON likewise leaves a mutation's outcome unknown.

| Operation | Retry behavior and recovery |
|---|---|
| `add --id NAME` | Repeating a valid named create returns the existing issue unchanged. Creation fields are ignored for an existing ID: this is not an upsert and the result has no `created` flag. Inspect with `show`; use `set` for an intended update. An unreadable or occupied ID is refused, not overwritten. |
| `add` without a name | No caller-supplied identity for deduplication. Inspect before retrying an unknown outcome; do not assume the retry identifies the original creation. |
| `comment` | Appends a history event each time. Inspect `show ID --json` and its `log_events` after a lost response before sending again. There is no request token for deduplication. |
| `start`, `stop`, `close` | Repeating a successful call appends another event, even if status is already the requested state. `start` and `stop` refuse closed issues. `start` provides no exclusive claim or lease. |
| `reopen` | Requires a closed issue. After success a retry reports an error because the issue is already open. Inspect state/history rather than treating that error as proof the first call failed. |
| `set` | Same-value title/type/component updates can be no-ops; description and status updates append events. Replaying an old update can also overwrite newer work. Read before deciding what remains necessary. |
| `assign` / `unassign` | Repeated assignment appends history; unassigning an already unassigned issue is a no-op. Neither coordinates agent ownership. |
| `blocks` / `unblocks` | Existing/absent relationships are no-ops at the issue-operation level, but the two issue saves are separate. Inspect both endpoints and run `deps --check --json` after a failure; a failure can leave a one-sided edge. |
| `ref` | Deduplicates by path and line; repeating it with a different note does not update the existing reference. Inspect `file_refs`. |
| `drop` | A repeated deletion reports a missing issue. Inspect the exact ID before deciding whether the first attempt succeeded; deletion does not cascade through other issues' references. |
| `import` | Can create some issues and then report failures. Inspect all four arrays. `warnings` cause exit `1`; `notices` alone do not. Existing IDs are skipped, but reciprocal edges on existing issues can still be completed. A successful exit is not a full-fidelity migration guarantee; read `ditz import --help=plain` before planning a migration. |

The write lock serializes cooperating local ditz writers. It does not make a
sequence of CLI calls one transaction, reserve an issue for an agent, or stop
writers in other clones. Inspecting history helps recovery but is not an
exactly-once protocol under concurrent changes.

## Local writes and remote sync

On the Git backend, a successful issue mutation commits changed state locally;
a successful no-op need not create a new commit. It has not published local
commits to `origin`; run `ditz sync` as a separate step. Filesystem-backed writes
update files without a metadata commit.
Verify the intended repository and `~/.ditz-config` before writing: the Git
backend takes precedence when a metadata branch exists; otherwise a configured
issue directory can select a different filesystem store.

`status.sync` is `null` for a filesystem backend or an unavailable sync state,
`{"tracking":false}` when no remote metadata ref is recorded locally, or
`{"tracking":true,"ahead":integer,"behind":integer}`. These are local-ref
observations: `status` does not fetch, and zero counts do not prove the remote
has not changed since the last sync.

`sync.pulled` and `sync.pushed` count commits, not issues; `head` identifies the
resulting local metadata commit. `ahead` and `behind` use the locally recorded
remote ref and can be null if unavailable. `--pull-only` can leave local commits
unpushed; `--push-only` does not fetch remote changes. A sync failure can happen
after a fetch or merge, or after local issue writes have already committed.
Preserve diagnostics, inspect the resulting state, fix the reported problem,
and retry sync without replaying successful issue mutations.

## Setup results

`init.onboarding` is `skipped` with `--no-onboarding`, or `wrote`,
`already-present`, `refused-symlink`, or `failed`. Once initialization succeeds,
an onboarding refusal/failure does not make `init` exit nonzero. Inspect this
field separately if installing instructions is required.

`onboard.onboarding` is `wrote`, `already-present`, `refused-symlink`, or `failed`.
Explicit `onboard --refresh` retains these outcomes: replacing a recognized old
block is `wrote`, a current block is `already-present`, and an edited or malformed
block is `failed`. See [Updating agent instructions](onboarding.md).
The standalone command exits `1` for `failed`, but `refused-symlink` currently
exits `0`. Its `path` is the actual destination when resolved successfully,
otherwise the requested path. A success status alone does not prove a block was
written. Setup commands are not a recovery substitute for locating the intended
existing tracker.

The implementation references for this contract are
[command handlers](../bin/main.ml), [JSON serializers](../lib/types.ml),
[issue operations](../lib/issue_ops.ml), and [storage](../lib/storage.ml).
