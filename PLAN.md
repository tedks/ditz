# ditz roadmap

## Intent and current baseline

Agents and people should be able to read and write issues as plain text files.
One issue is one YAML file; git carries the history. Keep ordinary tracking
non-interactive, inspectable, and usable without a daemon, database, or service.
Replace beads where these workflows fit, rather than copy every beads feature.

This roadmap was reconciled on 2026-10-02 against merged source at `83dd20e`
and the open PRs below. A shipped implementation is not proof of fleet rollout
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
complete resulting issue. That consistency is a subject for the usage study.

## Next work, in order

### 1. Finish the existing safety and feedback PRs

The following sequence was authorized on 2026-10-02. These are open draft PRs
at the baseline above, not merged guarantees. Finish review and local gates
before marking a row delivered.

| Sequence | PR | Result | Remaining evidence/work at baseline |
| --- | --- | --- | --- |
| A1 | [#28](https://github.com/tedks/ditz/pull/28) | Refuse `add --id` over an occupied but unreadable issue | Complete interrupted foreign review and verify exact head |
| A2 | [#27](https://github.com/tedks/ditz/pull/27) | Explain that `--id` is the issue name and re-add is not update | Rebase after #28 and revalidate |
| B1 | [#29](https://github.com/tedks/ditz/pull/29) | Strict filters, `-s open`, and comma-separated filter values | Complete review and verify exact head |
| B2 | [#30](https://github.com/tedks/ditz/pull/30) | Commit only the path owned by a write | Fix rollback losing symlink/file-mode/hard-link identity; review the fix |
| B3 | [#31](https://github.com/tedks/ditz/pull/31) | Pull with an explicit refspec and report sync state | Rebase after #30 and revalidate |
| B4 | [#32](https://github.com/tedks/ditz/pull/32) | Serialize concurrent tracker mutations | Fix configured-directory lock coverage, locks held during stdin reads, and hook reentrancy; stabilize lock tests |

Land A1 then A2, followed by B1 through B4. Use normal PR merges, rebase one
successor at a time, and retain the branches until the stacks are complete.
The current tracker records review details in `land-id-docs-stack`,
`commit-own-path-only`, and `write-lock-recheck`.

The former `ci-actions-disabled` blocker is superseded by the local-gates
policy below. Enabling CI is not a prerequisite for this work.

### 2. Design ergonomics from observed agent interactions

An investigative lane is examining recent ditz and beads tool calls, building
on the June and September studies. Start with an agent's intended task and the
interaction it would want to write; only then choose the implementation.
Python-like examples can describe a desired interface without committing us to
a Python SDK.

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

### 3. Verify rollout before declaring release readiness

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
does not serialize concurrent read-modify-write operations; PR #32 addresses
that distinct risk.

Sync merges append-only log events, resolves status/disposition changes, and
three-way merges reference lists without resurrecting deletions. Conflicting
scalar edits can still require manual resolution; use the error's instructions
and the format documentation. There is no `ditz resolve` command or automatic
sync configuration API to assume.

### Onboarding

`init` and `onboard` append a marked block without replacing unrelated policy.
An existing block is skipped. PR #20 permits following an in-repository symlink
to its target while refusing an external target; the old blanket symlink refusal
is obsolete. Refreshing an existing stale block remains an open design item.

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
