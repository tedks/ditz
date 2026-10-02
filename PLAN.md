# ditz roadmap

## Intent and current baseline

Agents and people should be able to read and write issues as plain text files.
One issue is one YAML file; git carries the history. Keep ordinary tracking
non-interactive, inspectable, and usable without a daemon, database, or service.
Replace beads where these workflows fit, rather than copy every beads feature.

This roadmap was reconciled on 2026-10-02 against the completed safety stack
at `8dd0739` and the documentation linked below. A shipped implementation is not proof of fleet rollout
or a completed migration. Earlier plans and decisions remain in git history;
unchecked historical ideas are not an implementation queue.

[README.md](README.md) describes the command surface,
[FORMAT.md](FORMAT.md) describes storage and relationships, and
[INSTALL.md](INSTALL.md) describes distribution. `ditz COMMAND --help` is the
reference for each invocation. Examples in new design proposals must be labeled
as proposals until implemented.

## Delivered

| Capability | Evidence in merged source |
| --- | --- |
| Issue lifecycle, comments, field updates, file references, release assignment, search | `bin/main.ml`, `lib/issue_ops.ml` |
| Non-interactive typed creation with descriptions and stdin; named, idempotent creates | `add -t`, `-c`, `--desc`, `--desc-stdin`, `--id` |
| Status changes and their reasons | `reopen`, `close --reason`, `set --status` |
| Plain scalar YAML, with legacy variant-map reads | `lib/types.ml`; [FORMAT.md](FORMAT.md) |
| Git identity fallback | PR #7; `lib/storage.ml` |
| Git metadata branch and shared persistent sparse worktree | `lib/git.ml`; PR #4 worktree/root detection |
| Atomic file replacement and sync conflict resolution | PRs #8 and #9; `lib/fs_util.ml`, `lib/merge.ml` |
| Graph-derived readiness, cycle prevention, dependency inspection | PRs #15 and #16; `lib/graph.ml`, `deps --check`, `deps --dot` |
| Joining an existing tracker from a fresh clone | PR #18 |
| Agent onboarding and format documentation | PRs #19 and #20; `init`, `onboard`, `lib/onboarding.ml` |
| Beads JSONL import and incremental-import hardening | PRs #17 and #24; `lib/import_beads.ml` |
| Nix distribution and installation instructions | PRs #22 and #23; [INSTALL.md](INSTALL.md) |
| OCaml implementation at the repository root; legacy Ruby implementation removed | PRs #25 and #26 |

Structured output exists across the command surface, but mutation response
shapes differ. Accepting `--json` is not a promise that every write returns the
complete resulting issue. The usage study proposes a separate opt-in contract;
that proposal is not implemented. The current command-by-command behavior is
documented in [JSON results and retries](docs/json-contracts.md)
([PR #37](https://github.com/tedks/ditz/pull/37)).

## Safety and feedback work completed on 2026-10-02

All six PRs below landed as normal merges after review and local gates. The tested
heads and merge commits are recorded here so delivery is distinguishable from a
proposal or a historical green test. Each PR carries its own review/gate comment.

| PR | Result | Tested head | Merge commit |
| --- | --- | --- | --- |
| [#28](https://github.com/tedks/ditz/pull/28) | Refuse unreadable or staged-only issue occupants; fail closed when the index cannot be inspected | `f50fca5` | `8e252ea` |
| [#27](https://github.com/tedks/ditz/pull/27) | Explain that `--id` is the issue name and re-add is not update | `2439961` | `08eb430` |
| [#29](https://github.com/tedks/ditz/pull/29) | Strict filters, `-s open`, and comma-separated values | `e590b65` | `89e4554` |
| [#30](https://github.com/tedks/ditz/pull/30) | Commit only the owned path; rollback preserves file-entry identity and refuses unsupported special files | `b511f86` | `94de2b3` |
| [#31](https://github.com/tedks/ditz/pull/31) | Explicit fetch refspec, truthful sync state, and stale remote-ref handling | `9f9833b` | `42db9df` |
| [#32](https://github.com/tedks/ditz/pull/32) | Serialize mutations for the actual store, read stdin outside the lock, and fail promptly on hook reentry | `5eeb62d` | `8dd0739` |

Every head passed `nix develop --command dune build` and
`nix develop --command dune runtest --force`, including after rebases. Substantive
changes reached a clean Codex/Google council fixpoint; the Anthropic seat was
unavailable due to credits and remained empty. The wording-only #27 received a
proportionate light review. Regression tests for repairs were mutation-checked.
The blocked-pipe observation test is conditional on Linux `/proc` availability;
these local checks are not evidence of verification on every platform.

The former `ci-actions-disabled` blocker is closed under the local-gates policy.
Four nonblocking review followups remain tracked: `remedy-relative-path-quoting`,
`filter-linear-accumulation`, `sync-report-maintenance`, and
`filesystem-lock-hygiene`.

## Next work, in order

### 1. Improve ergonomics from observed agent interactions

The [agent ergonomics investigation](docs/agent-ergonomics-investigation-20261002.md)
is delivered in [PR #34](https://github.com/tedks/ditz/pull/34). It analyzes 91
operational tool interactions, builds on the June and September studies, and
writes desired caller conversations before implementation slices. Its bounded
sample and unknown outcomes are explicit; it is not a fleet failure-rate estimate.

The first practical slice teaches the existing CLI: exact ID capture, literal
stdin, plain help, readiness boundaries, and per-item recovery. The
[agent recipes](docs/agent-recipes.md) shipped in
[PR #35](https://github.com/tedks/ditz/pull/35); their examples were reverified
against the final safety-stack source before merge.

Open product questions and proposed contracts are recorded separately:

- `oq-ergonomics-tracker-discovery`: a read-only location result, without repair
  or automatic initialization.
- `oq-ergonomics-result-contract`: an additive, consistent mutation result that
  preserves existing `--json` consumers and makes retry effects explicit.
- `oq-ergonomics-incomplete-read-policy`: distinguish a complete empty result
  from a partial scan before changing selection behavior.
- `decision-hide-closed-limit-count`: bounded reads and stable ordering, keeping
  the closed-issue visibility decision separate.

Start with an agent's intended task and the interaction it would want to write;
only then choose the implementation. Python-like examples can describe a desired
interface without committing us to a Python SDK.

For each proposed improvement, record:

- A concrete observed attempt, result, workaround, and source date. Separate
  ordinary successful use, visible friction, and missing result evidence.
- Whether the issue is already fixed, covered by a pending PR, or still open.
- Desired input and output, including error recovery, retry behavior,
  idempotency, and concurrency semantics.
- The smallest justified change, compatibility cost, and acceptance scenarios.

Keep raw transcripts and private project details out of the public repository.
Publish synthetic examples and aggregate findings with explicit sample limits.
Do not present a curated sample as a fleet-wide failure rate.

Candidates to evaluate include bounded output, help and flag discoverability,
re-add mismatch feedback, useful mutation JSON, and refreshing stale onboarding.
`count` and `list --limit` were approved in the June plan but are not implemented
at this baseline. Changing which issues `list` shows by default is a separate
product decision; adding a limit does not authorize hiding closed issues.

Keep unsolicited guidance in human error or empty-state output, never in
`--json`, `--ids-only`, or routine successful output. Machine output must remain
parseable and free of instructional prose.

### 2. Verify rollout before declaring release readiness

Distribution and import code have shipped. Their presence does not establish
that every machine uses the same revision, a real tracker migrated without
loss, or agents have used it for a week without manual repair.

Before a release:

- Record the exact installed revision and applicable platform checks.
- Verify a specifically authorized real-project migration against source data,
  including issue contents, comments, IDs, relationships, and provenance.
- Keep evidence of a week of daily agent use without manual repair, the original
  release acceptance criterion. Confirm the pilot project and authority before
  changing its tracker of record.
- Reconcile project instructions with the installed command surface.
- Record the validated revision and remaining limitations in the changelog.

There is no release tag at the 2026-10-02 baseline. No migration, daemon shutdown,
new importer design, or release is authorized merely by this roadmap.

## Contracts and design decisions

### IDs and retries

The current generated ID is a SHA1 of time, randomness, and content; it is not a
content-addressed deduplication key. IDs are immutable. `--id NAME` supplies a
stable caller-chosen handle; unique prefixes can address existing issues.
After synchronization a previously unique prefix can become ambiguous, so
callers should keep the full returned ID.

Re-adding an existing readable ID leaves it unchanged; use `set` to edit it.
PR #28 addresses the unreadable-occupant exception, and PR #27 makes the
contract easier to discover. The June 11 prefixed-random-ID proposal was
superseded by the June 14 decision to retain generated hashes plus `--id`.
Readable defaults and rename remain product questions, not shipped behavior.

### Dependencies, grouping, and priority

`blocked_by` is authoritative for the graph. The CLI maintains reciprocal
`blocks` edges; hand edits and merges can still require `deps --check`.
`ready` excludes blocked work and ranks candidates by the number of open issues
they transitively unblock, then by creation time and ID. Traversal is cycle-safe.
On a flat graph this becomes oldest-first, an accepted limitation.

Use `component` for grouping. Model an epic as blocked by its members only when
that is a real completion dependency. Components have one grouping axis, and
an epic edge affects readiness ranking; neither convention supplies general
multi-membership or a separate parent field.

The stored-priority field was deliberately cut on June 14. Priority is input,
not derived state; the reason for the cut was staleness, with the known cost
that an urgent leaf may rank below a low-value hub. Revisit only with concrete
usage evidence and an explicit product decision. `deps` was subsequently
restored and shipped because graph traversal already existed.

### Storage and synchronization

Git-backed trackers use an orphan `ditz-metadata` branch and a persistent sparse
worktree. Writes commit locally; `sync` fetches, merges, and pushes.
The filesystem backend also remains supported. Atomic file replacement alone
does not serialize concurrent read-modify-write operations. PR #32 adds a
store-scoped lock for CLI mutations; manual file edits do not acquire that lock.

Sync merges append-only log events, resolves status/disposition changes, and
three-way merges reference lists without resurrecting deletions. Conflicting
scalar edits can still require manual resolution; use the error's instructions
and the format documentation. There is no `ditz resolve` command or automatic
sync configuration API to assume.

### Onboarding

`init` and `onboard` append a marked block without replacing unrelated policy.
An existing block is skipped by default. Explicit `onboard --refresh` replaces
only a recognized, unchanged generated block and refuses edited or malformed
blocks. PR #20 permits following an in-repository symlink to its target while
refusing an external target; the old blanket symlink refusal is obsolete. See
[onboarding refresh](docs/onboarding.md) for exact recognition and output rules.

### Import limits

Use `ditz import FILE --format beads` (or stdin), not the historical proposed
`ditz import beads FILE` syntax. PR #24 supports incremental imports, remaps
unsupported IDs with provenance, reconstructs parent-child blocking edges,
and reports detected losses with a nonzero exit status. Re-import preserves
existing issue contents and status, but incremental import can add reciprocal
dependency edges to existing issues.

This is not a universal losslessness guarantee: comments and unknown-field
handling have outstanding fidelity questions, imported cycles need a policy,
and preserving dotted IDs verbatim would differ from today's remapping. The
later import-fidelity proposal remains separate from the completed PR #24 and
requires explicit authorization before implementation or a real migration.

## Quality and merge gates

GitHub Actions validation and automated PR reviews are disabled by policy.
Do not add or enable them. Deploy/release workflows, if introduced under an
authorized release task, follow the separate deployment policy.

Run project tooling in the Nix environment:

```sh
nix develop --command dune build
nix develop --command dune runtest --force
```

Use meaningful targeted regressions for fixes, and demonstrate that they fail
without the fix. Tests must use synthetic trackers, not live issue data.
Before a substantive merge, run the multi-provider council to a clean fixpoint:
review the change, fix Critical/Important findings, then review each fix delta.
File remaining nits with their rationale. An unavailable provider is a recorded
empty seat, not a same-provider replacement.

Post the council outcome, seats, exact tested SHA, and local gate commands on
the PR. Re-run gates if a rebase or pull changes that head. A clean council does
not substitute for tests, and passing tests do not substitute for review.
Documentation-only changes receive a proportionate light review.

For distribution, `nix build .#ditz` builds the package. Do not assume a static
binary or cross-machine portability; follow [INSTALL.md](INSTALL.md).

## Deferred work and non-goals

Keep `edit`, release creation/shipping commands, component management commands,
HTML/Markdown export, color/pagination, custom hooks, and configurable metadata
branch names out of the immediate queue until a concrete workflow justifies
them. Module interfaces, typed errors, and stronger status/disposition types
remain debt; completing scalar YAML did not complete that debt.

No daemon, sqlite, web UI server, external service bridge, `bd` compatibility
shim, or beads orchestration layer. Do not store derived counts or readiness.
Interactive prompts must not become a requirement for ordinary tracking.

Track product decisions as issues, including readable IDs, actor attribution,
closed-issue visibility, onboarding refresh, and import fidelity. A plan or an
investigative finding is evidence for a decision, not the decision itself.
