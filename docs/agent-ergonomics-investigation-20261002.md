# Agent ergonomics investigation — 2026-10-02

**Status: investigative proposal; no implementation authorized by this report.**
Source baseline: `83dd20e3302fce8258b207ed7e660d8064b6913c`.
The examples marked **PROPOSAL** are desired interfaces, not executable documentation
for the current release. All issue names, contents, paths and response values in
examples are synthetic. Private transcripts and source locators are deliberately
not included.

The highest-value next work is to make the existing file-and-git model dependable
and easy to compose: finish the already-proposed safety work in its separately authorized lane,
teach the existing ID/stdin/JSON surfaces at the point of use, expose where the
tracker actually is, and bound reads. A consistent mutation result is worth a
product decision. A new SDK, daemon, database, general batch engine, assignment
system or ID scheme is not justified by this sample.

## Method and evidence limits

This uses the requested *write the API you wish you had* method, attributed in the
brief to Aaron Swartz: start with the agent's task and desired conversation, then
ask what the smallest implementation would need to do. Caller conversations were
recorded before implementation-slice design. The method is used here without
claiming a verified historical quotation. The caller is an agent reading tool
output, preserving task state across turns and composing noninteractive commands.

The requested window was **September 2–October 2, 2026**, emphasizing September 15
onward. This was a bounded local sample, not a fleet-wide transcript sweep:

- Six project-directory strata: the tracker itself, configuration/tooling, an
  application, organization tooling, a second application and a third application's
  onboarding. These are anonymous roles, not public project inventories.
- Metadata screening found 667 eligible local files (463 Codex, 204 Claude). Within each
  provider/stratum, inspect up to the latest twelve, stopping after three files
  containing candidate tracker strings. This screened 103 files and selected 17
  candidate-positive files. Selection was by first recorded session date, not by
  every session active in the window; older resumed sessions can be missed.
- Native tool calls were joined to returned results by call ID, with relevant
  asynchronous continuations retained separately. Of 166 candidate records,
  **91 operational-attempt tool interactions in eleven files** survived manual
  classification. Six discovery/prerequisite records support context but are
  outside that denominator; 69 records were excluded as prose, unexecuted script
  text, forensics, control work or other non-operational material.
- Operational coverage is **September 5–26**: **79/91 interactions are September
  15 or later**. There is no operational claim for September 2–4 or September
  27–October 2. Fifteen October 2 control-related candidates were deliberately
  excluded to avoid contaminating the sample with this dispatch and nearby work.
- **69 ditz / 22 beads; 66 Anthropic / 25 OpenAI** interactions. No Google
  operational sample. Cross-project commands inside a resumed transcript were
  attributed by their command target rather than assuming the session's launch
  directory identified the tracker.
- Deduplication used provider + call ID, then provider + timestamp + exact command.
  No duplicate operational records remained under either key. Copied descriptions
  and command examples inside handoffs were excluded. Copies outside the selected
  files are not counted or claimed to have been found.

| Transcript-origin cohort | Claude interactions | Codex interactions |
|---|---:|---:|
| Tracker development | 3 | 0 |
| Configuration/tooling | 0 | 0 |
| Application A | 26 | 16 |
| Organization tooling, including cross-project work | 28 | 9 |
| Application B | 7 | 0 |
| Application C, tool discovery | 2 | 0 |
| **Total** | **66** | **25** |

There were **68 visible ordinary results, ten visible friction interactions and
thirteen unknown terminal outcomes**. Ordinary results include successful help,
reads, creates, comments, lifecycle changes and syncs, sometimes with cumbersome
shell wrappers. Friction includes shell/JavaScript failures before ditz ran and
output truncation; it is **not** a ditz error rate. Unknown includes redirected,
truncated or backgrounded output without sufficient joined terminal evidence.
A tool interaction can contain several commands or a loop: 91 is not a count of
CLI invocations, users or independent incidents. No probability estimate follows
from this purposive sample.

Other misses: aliases and dynamically constructed commands can evade string
selection; message-only reviewer sessions consume candidate slots; Claude native
subagent directories were not recursively mined; no other host was queried.
Most executable revisions are unknown. The observed `0.1.0-ocaml` version string
cannot identify a particular patch. Synthetic probes below characterize the named
source baseline, not every binary used in the histories.

### Building on existing studies

The June study survives in [PR #5](https://github.com/tedks/ditz/pull/5),
[PR #10 and its review](https://github.com/tedks/ditz/pull/10), and [PLAN.md](../PLAN.md).
It established the ready/start/close loop, typed creation, reason-bearing closure,
JSON composition and explicit sync. This investigation did not re-mine June.

The September 13/14 review's tracker record, `usage-review-2026-09`, reports roughly
4,000 calls, mostly from another host. Its findings include write races, permissive
filters, re-add misunderstanding, weak sync feedback, post-write verification,
flag guesses, output size and stale onboarding. Those counts are **inherited
findings**, not added to this sample's denominator. One September 10 filter incident
re-inspected here may be the same incident in that review; it is baseline evidence,
not independent corroboration.

The later import-fidelity forensics and private handoffs also remain relevant.
They distinguish row-count parity from retained comments and relationships. They
are not a mandate to implement import changes, and their rehearsal reads are not
counted as ordinary tracker use here.

### Evidence groups

Private ledger entries preserve exact source/call/result locators, date, intended
task, attempted command, output, workaround, friction cost, sample frequency,
confidence and version limits. Public references below use these aggregate groups:

| Group | Observed evidence | Interpretation and limit |
|---|---|---|
| G1 — discovery | Four preparatory tool interactions searching help, paths, git config and onboarding before a successful create/comment/sync; separate missing-directory and stale beads-onboarding episodes | Locating the actual store costs work. A dedicated discovery result is a proposal, not an observed user request. |
| G2 — reading/output | Two interactions where shell startup output consumed `head` budgets; one recovered in the next call. One interaction verifies four creations with four `show --json` calls | Environment chatter is not ditz JSON corruption. Mutation receipts may reduce verification reads; motivation is partly inferred. Earlier review independently proposed post-write state. |
| G3 — composition/IDs/help | One successful create followed by list/grep/awk ID extraction; one new `ditz help` rejection | Existing `--ids-only` or `add --json` solves ID capture. Help alias remains an existing backlog item. |
| G4 — bulk/text | One shell quoting failure repaired by running a generated script; one JavaScript wrapper parse failure repaired with literal text/stdin. Seven successful multi-create interactions contain 26 creates | Real friction, but outside ditz's parser. Successful loops are evidence against immediately adding a general batch engine. |
| G5 — beads recovery | One empty captured create ID followed by an incorrectly blank cross-reference, search and retry. Three long-text validation-failure interactions; one explicitly reports 955 characters against a 500-character title limit | The first create's underlying error was hidden. Two later validation messages were truncated; their exact causes remain uncertain. Short titles + descriptions recover successfully. |
| G6 — persistence/sync | Earlier race reproductions and live pending PRs; recent ordinary sync results still say only that metadata synced | High impact, already proposed. No fresh concurrent-loss reproduction in the post-September-15 sample. |
| G7 — dependencies/readiness | Ordinary readiness use; one dependency write with incomplete terminal evidence; positive synthetic graph probe | No newly observed navigation failure. Missing evidence does not prove the graph surface sufficient for every workflow. |
| G8 — migration | Existing forensic tool results and handoffs show successful issue counts can coexist with missing native comments | Already investigated and separately gated. Do not restart migration or import implementation. |

## Desired caller conversations — PROPOSALS first

These conversations express the contract from the caller's side. They do not
prescribe a Python SDK, storage rewrite or new service. Existing commands are
identified explicitly; proposed flags and responses must not be mistaken for
current behavior.

### 1. Find the tracker before touching it

**Caller intent:** “Tell me which store this worktree will use, and whether your
answer involved a network read.” G1 is the direct evidence; G6 supplies the safety
constraint.

**PROPOSAL:** a read-only `where` command:

```console
$ ditz where --json
{"backend":"git","issue_dir":"/work/widget/.ditz-worktree/.ditz","branch":"ditz-metadata","head":"1111111111111111111111111111111111111111","worktree_present":true,"network":"not-contacted"}
```

This is an exact synthetic success example. For filesystem storage, `backend` is
`"filesystem"`, `issue_dir` is the resolved configured directory, `branch` and
`head` are null, and `worktree_present` is null. For an existing metadata branch
without a materialized worktree, the git result has `issue_dir:null` and
`worktree_present:false`: reading it must not create a worktree just to fill a
path field. A branch available only in cached remote refs is reported as a
separate `backend:"git-remote-ref"`, with its cached head and null issue directory;
it is not represented as a local writable tracker.

**PROPOSAL error** (exit 1, one JSON object on stdout):

```json
{"error":{"code":"NO_TRACKER","message":"No tracker found in the resolved repository","recovery":"Run ditz init only if creating a tracker is intended"},"network":"not-contacted"}
```

An unreadable store/configuration or unresolved ownership is `STORE_UNREADABLE`
or `STORE_AMBIGUOUS`, not `NO_TRACKER`. No automatic migration, repair, init, fetch
or choosing between independent repositories. Normal git context selects the
repository; nested/overlapping repositories cannot be detected reliably in every
case. The result describes the selected context, not a certificate that no other
repository exists nearby.

Retries are side-effect-free. Paths/head are a point-in-time observation; another
process may move them immediately. This command conveys location, not a lease or
permission to edit shared files. Four observed preparatory tool interactions can
become one discovery call; understanding creation flags remains separate.

### 2. File a finding, capture its name, and recover honestly

**Caller intent:** “Record this finding once, give me its stable handle, and make
it clear whether you changed anything.” Evidence: G3/G4, earlier re-add findings,
and the source probe's small mutation JSON results.

**CURRENT, usable today:** use a deterministic ID and literal stdin. Avoid nested
shell quoting. In a Nix project, execute this script inside its required
`nix develop --command ...` environment.

```sh
set -eu
issue_id=$(ditz add 'Handle a missing widget' --id widget-missing \
  -t bugfix -c parser --desc-stdin --ids-only <<'DESCRIPTION'
A quote ('), a dollar sign ($), and a newline are literal text here.
The widget should remain absent until its input is available.
DESCRIPTION
)
[ "$issue_id" = widget-missing ]
ditz comment "$issue_id" --stdin <<'COMMENT'
Observed with synthetic input. Acceptance: no invented default value.
COMMENT
```

Current re-add with `--id` returns the existing issue unchanged; it is **not an
upsert**. Current versions also return before reading stdin on that path. A
here-document or owned input file is preferable to an unbounded producer that
expects its entire stream to be consumed. Use `set` to edit. Pending #28 is needed
to make the unreadable-file refusal safe, and #27 teaches naming/no-op semantics.
Never advise a caller to retry creation using a new random ID after a lost result.

**PROPOSAL:** preserve bare `--json` and add an opt-in, versioned machine result,
spelled `--output json-v1` here pending Q1. Combining it with `--json` or
`--ids-only` is a parse error (exit 124), rather than an undocumented precedence
rule. New syntax does not change command mutation semantics. An example for changing a description:

```console
$ printf '%s' 'Synthetic reproduction steps.' | ditz set widget-missing --desc-stdin --output json-v1
{"schema":"ditz.result.v1","operation":"set","results":[{"input":"widget-missing","id":"widget-missing","ok":true,"persistence":"committed","head":"2222222222222222222222222222222222222222","issue":{"id":"widget-missing","title":"Handle a missing widget","status":"unstarted","desc":"Synthetic reproduction steps."}}],"errors":[]}
```

The exact projection rule is part of the proposal: every successful item includes
`id`, `title`, `status`, plus fields that command requested to change, holding their
**resulting** values. `close` additionally returns disposition; `comment` returns
the appended event (`time`, `who`, `what`, `comment`) instead of the entire log.
`add` returns its creation fields and `created:true|false`; on an existing ID,
`mismatched_fields` names supplied fields that differ, without modifying them.
For re-add with `--desc-stdin`, preserve the current early return: report
`mismatched_fields:null` and `input_comparison:"stdin-not-read"` rather than claim
the unread text matches. Named argument fields can still be compared. No
transcript, full history, unsolicited guide or banner is attached to success.

`persistence:"committed"` means the reported state was committed locally at the
returned head; it does not mean pushed. Filesystem writes report `"saved"` and
`head:null`, never a fabricated git commit. Reads after completion can observe a
later writer; receipts describe the state this operation produced, not eternal
current state. A command that cannot prove commit/save success returns an error,
not `ok:true`.

**PROPOSAL error** (exit 1):

```json
{"schema":"ditz.result.v1","operation":"set","results":[],"errors":[{"input":"widget-missing","code":"STORE_UNREADABLE","message":"Issue file exists but cannot be read","effect":"none","retry":"repair-or-inspect"}]}
```

After a commit failure, `effect` is `"none"` only if rollback is verified; otherwise
it is `"unknown"` and `retry:"inspect"`. A proven lock timeout before mutation is
`LOCK_TIMEOUT`, `effect:"none"`, `retry:"backoff"`. Diagnostics stay on stderr;
stdout contains one envelope for domain errors after the command is parsed.
Cmdliner parse failures can still exit 124 with empty stdout and a stderr message;
callers must handle that explicitly. The initial scope does not promise JSON for
crashes, broken pipes or errors before the output mode is recognized.

Retries retain existing semantics. Named add is an ensure-exists operation, not a
field update. Repeated close/start currently succeeds but may append another log
event; comment retries append again. There is **no exactly-once promise**. After
an ambiguous result, inspect the issue/log before deciding whether to repeat.
Persisted request IDs or event deduplication are deferred, not secretly implied by
a receipt schema. Independent simultaneous writes must first satisfy the existing
storage-safety work; an output format cannot prevent lost updates.

Compared with today's `set --json` → `show --json` → projection, the desired
receipt removes the second process/read when the caller needs the resulting
changed field. It does not eliminate a later integrity audit or prove remote sync.
The observed create → list/grep ID lookup needs **no new API**: `--ids-only` already
removes that lookup.

### 3. Read only the work needed for this decision

**Caller intent:** “Give me a bounded, valid selection. Never turn a misspelled
filter into all issues.” G2, the prior output-size study and the baseline G6 filter
incident support this. Recommended default visibility stays unchanged: closed tasks
are not hidden implicitly.

**PROPOSAL** after #29's strict filtering:

```console
$ ditz list --status open --limit 2 --ids-only
widget-missing
widget-retry
$ ditz list --status opne --limit 2 --ids-only
```

The second command exits 1, stdout is empty, and stderr names the invalid value
and valid choices, including `open`. That validation behavior is already proposed
in #29; it is not a new patch requested here.

For `--json`, retain the existing array/item schema and cap its length. Do not add
an envelope to existing JSON just to report a count. `--limit` takes a nonnegative
integer; zero returns an empty result, negative/non-integer values fail parsing,
and no option means no new cap. `list` sorts by immutable ID before limiting;
`ready` keeps graph rank and age, including its already-shipped immutable-ID final
tie-breaker. The proposed list ordering choice is Q3. Limit does not mean pagination; callers
must not infer completeness from an array reaching its limit. `count` shares list
filters and emits one integer (`--json` is a JSON number); it counts all matches,
not an accidentally truncated selection.

```console
$ ditz ready --limit 2 --ids-only
widget-missing
$ ditz count --status open --json
7
```

These are also **PROPOSALS**. `ready` is a snapshot of unstarted/paused, unblocked
issues, not an exclusive claim. `start` marks status; two agents reading the same
snapshot can both start the same issue. Use the existing coordination policy for
ownership. A new reservation/lease protocol lacks evidence here.

Empty ready results remain valid data, not a storage-error fallback. Human mode
may explain how many issues are blocked; JSON remains parseable data. A complete
error policy for unreadable members during a scan needs Q4 below: counting an
incomplete scan as a complete empty tracker is unsafe.

### 4. Finish several items without pretending the batch is atomic

**Caller intent:** “Tell me which items succeeded so I retry only the remainder.”
Evidence: successful multi-create loops in G4, partial beads updates in G5, and
the existing multi-ID close probe. This does **not** justify a new batch language.

**CURRENT:** `ditz close widget-a widget-b --reason 'Verified' --json` already
accepts several IDs. A missing second ID produces exit 1, a `closed` list containing
the first ID, and an `errors` list for the missing one. Do not replay the entire
batch merely because exit status was nonzero.

**PROPOSAL**, using the same optional result contract:

```console
$ ditz close widget-a missing-item --reason 'Verified' --output json-v1
{"schema":"ditz.result.v1","operation":"close","results":[{"input":"widget-a","id":"widget-a","ok":true,"persistence":"committed","head":"3333333333333333333333333333333333333333","issue":{"id":"widget-a","title":"Handle a widget","status":"closed","disposition":"fixed"}}],"errors":[{"input":"missing-item","code":"NOT_FOUND","message":"No matching issue","effect":"none","retry":"correct-id"}]}
```

Exit 1 means inspect both collections. Items retain input order within each
collection; repeated input IDs are not silently invented into an atomic transaction.
The first implementation documents current duplicate-input behavior rather than
changing it behind an output flag. Corrections/retries concern failed items only.
Already committed successes are not rolled back because another ID was missing.
Concurrency protection spans the existing mutation contract; no cross-clone
transaction or graph-wide snapshot is claimed.

For multiple new findings, first use a script with one deterministic `add --id`
and literal input per item, checking each exit/result. No shell `eval`, title-based
ID recovery, or failure-hiding `| tail` is required. Reassess a structured multi-add
input only after these recipes fail in a measured follow-up sample. If later
approved, it must specify per-item errors, duplicate IDs, graph edges, bounded
input and retry semantics before implementation—not simply accept arbitrary JSON.

### 5. Sync with evidence of what moved

**Caller intent:** “I have committed local changes. Did this sync pull, push, or
leave work unpublished?” G6 already led to [PR #31](https://github.com/tedks/ditz/pull/31).
Reuse that proposal rather than designing a second sync interface:

```console
$ ditz sync --json
{"pulled":2,"pushed":1,"head":"4444444444444444444444444444444444444444","ahead":0,"behind":0}
```

This is a **PROPOSAL already in #31**, not the baseline's current JSON. Counts
refer to commits, not issue updates. Local `status` information is explicitly
“as of the last sync”; it does not establish current remote state. Fetch/auth/offline
failure must not become successful “nothing to pull.” A push rejection after local
merge is not rollback; preserve local work, inspect the error, then retry sync
when appropriate. No automatic loop forever, auto-sync on every mutation, or
network contact in discovery/read commands.

## Relative priority and what already exists

Rank impact and observed frequency separately. Rare data loss outranks frequent
extra commands. The new sample's small size and clustered workflows do not support
precise population scores.

| Rank | Category | Impact / frequency evidence | Disposition |
|---|---|---|---|
| 0 | Worktree, concurrency, sync | Potential lost updates or unrelated commits; strongest evidence is prior reproductions, not new recent frequency | Existing #28/#30/#31/#32, unresolved findings at snapshot. Separately authorized landing work; no competing implementation. |
| 1 | Onboarding/discovery | Four-call discovery episode plus two contextual missing-path/stale-instruction episodes; can select wrong store or stall work | Recipes now; additive read-only `where` proposal. Refresh existing onboarding through its existing decision. |
| 2 | Learnability | One recent `help` failure; prior review has repeated flag/help guesses | Existing aliases/help issue; use plain help examples at point of error. Do not add a second naming flag. |
| 3 | Composability/JSON | One ID-lookup workaround; four post-create verification reads in one interaction; earlier study reports many post-write reads | Existing modes first; optional mutation receipt decision Q1. Environment banner belongs to project shell. |
| 4 | Bounded selection | Two concrete output-budget incidents; prior study has large-output/head/count evidence; baseline invalid filter returns wrong selection | #29 first, then opt-in limit/count. Keep default visibility. |
| 5 | Bulk changes / long text | Two wrapper failures; seven successful multi-create interactions; three beads validation-failure interactions | Teach stdin/files/argv and per-item results. Defer new batch input. |
| 6 | IDs/naming | One observed lookup cost; prior no-op/mismatch evidence | #27 + existing mismatch issue; retain immutable ID and `--id`. No new rename/default scheme from this sample. |
| 7 | Dependency navigation/readiness | Ordinary readiness use; no new confirmed navigation failure | Existing `deps`, `context --issue`, graph ranking; better examples, no graph renderer rewrite or lease system. |

### Source and PR reconciliation

The following was checked against the baseline source, git history and October 2
GitHub PR bodies/comments/reviews. **Subsequent landing update:** #28 merged at
`8e252eac0bedb4ecf1435256efe182cbb03b1eb7`, after an index-only occupant fix and
clean OpenAI/Google convergence reported by its landing owner. The table preserves
the initial snapshot to explain dependencies; it is not a live PR-status dashboard.
Baseline probes remain tied to `83dd20e`, before that fix. At the initial October 2 read, all six open PRs were **drafts**. Their GitHub
review/comment collections were empty; local council findings are recorded in the
tracker, and absence of GitHub comments is not clearance. PR bodies can describe
older iterations; the later handoff findings control their disposition.

| Surface/finding | State at investigation | Consequence |
|---|---|---|
| Typed add, custom IDs, stdin descriptions/comments, JSON, multi-ID close/start/stop/reopen, `set --status`, reason-bearing close | Shipped | Improve caller recipes before adding another abstraction. |
| Graph-ranked ready, `deps --check`/JSON/DOT, cycle prevention, onboarding, fresh-clone joining | Shipped in June | PLAN's old cuts/checkboxes are not a current feature inventory. |
| Old beads importer work, #24 | Merged | Does not authorize the later import-fidelity proposal or guarantee current export fidelity. |
| Unreadable-file protection for `add --id` | [#28](https://github.com/tedks/ditz/pull/28), `800940d`, open | Foundation for safe “unchanged” claims; incomplete council continuation remains. |
| Name/ID semantics in help/onboarding/format | [#27](https://github.com/tedks/ditz/pull/27), `777b298`, based on #28 | Already proposed; no new name flag. Existing blocks do not automatically refresh. |
| Strict list/set types, comma filters and `open` | [#29](https://github.com/tedks/ditz/pull/29), `51a0c13`, open | Do not duplicate; invalid-value baseline behavior reproduced synthetically. |
| Commit only own path, failure rollback | [#30](https://github.com/tedks/ditz/pull/30), `f392d50`, based on #29 | Open Important: rollback loses symlink identity/mode and mishandles hard-link identity. Not cleared here. |
| Explicit fetch refspec, sync counts, local sync visibility | [#31](https://github.com/tedks/ditz/pull/31), `d7da66f`, based on #30 | Already proposed; inherits unresolved base work. |
| Tracker-wide write serialization | [#32](https://github.com/tedks/ditz/pull/32), `0d10fcc`, based on #31 | Open Important: configured issue directory bypass; unbounded stdin under lock; hook reentrancy deadlock. Lock-file hygiene and sleep-based test synchronization also outstanding. |
| Limit/count, alias help, onboarding refresh, re-add mismatch | Existing tracker backlog/decisions; absent from baseline | Follow those issues; add evidence instead of duplicates. |
| New import fidelity / repository-layout cleanup | Separate open product questions | No implementation, cleanup, migration or new duplicate question here. |

[FORMAT.md](../FORMAT.md) and [README.md](../README.md) describe the shipped model.
Use source/merged heads and latest operator rulings to resolve conflicts with
[PLAN.md](../PLAN.md). In particular: SHA1 defaults are time/random/content-based,
not content-addressed; custom IDs are names; default list visibility is preserved;
the old CI plan does not authorize validation/review Actions. No Actions change
is proposed.

## Smallest justified implementation slices

These are ordered **design recommendations**. During this investigation, the owner
authorized a separate lead to finish and land #27–#32 and assigned roadmap
reconciliation separately. That authorization does not extend to new APIs or import
redesign here. Remaining implementation slices need their own authorization and
reviewable changes. This documentation PR does not grant implementation authority.

1. **Caller recipes and truthful reference docs.** Teach named add, `--ids-only`,
   literal stdin, `--help=plain`, checking per-item errors and the lack of exclusive
   claim semantics. Separate known current behavior from proposed flags. Coordinate
   naming text with #27 and onboarding refresh with the existing refresh issue.
   Point shell-startup chatter fixes at the owning project's environment, not a
   heuristic banner stripper in ditz. G1–G5; no schema/storage change.
2. **Finish existing safety stacks in the separately authorized lane.** #28 → #27 and
   #29 → #30 → #31 → #32 retain their current dependencies. Resolve the named
   Important findings and council convergence before relying on them. This report
   supplies acceptance needs, not a parallel lock/CAS implementation. G6.
3. **Read-only tracker discovery.** After Q2, add the narrow `where` result to
   existing backend resolution and document its local-only scope. Shared discovery
   must not invoke lazy mutation as a side effect. G1; can be developed independently
   of mutation APIs, with separate tests for non-mutation and ambiguity.
4. **Bounded reads.** Extend #29's strict filters with the already-requested
   limit/count work after Q3/Q4. Avoid pagination cursors, expression languages,
   projection DSLs and changes to default closed-issue visibility. G2 and prior
   output study. No new persisted data.
5. **Opt-in result contract.** After Q1 and safe persistence prerequisites, cover
   add/set/comment/lifecycle results first, using shared result/error serialization.
   Preserve current `--json` behavior and current mutation semantics. Surface
   verified commit/save state; do not promise rollback unless it happened. G2–G6.
   No separate SDK, request database or automatic retries.
6. **Measure again.** Repeat the bounded sample after uptake: commands per task,
   verification reads, unknown outcomes, quote-repair calls, bytes returned and
   successful ordinary work. Only then reconsider structured multi-add, field
   projections, stronger retry deduplication or readiness explanations.

A graph compiler, daemon, sqlite store, MCP service, plugin architecture, generic
transaction engine, bulk migration, priority field, assignee field and ID renaming
would all enlarge scope without demonstrated necessity here. Plain YAML and git
remain the storage and recovery interface. A Python-like caller can use
`subprocess.run(argv, input=text, check=False)` to avoid shell parsing; that is an
argument-passing technique, not evidence that a Python SDK is needed.

### Cost comparison

Counts below distinguish measured source sequences from **synthetic estimates**.
Token estimates are UTF-8 command bytes divided by four, rounded up: a transparent
size proxy, not a model tokenizer or billed-token measurement. Wrapper/setup cost,
issue text and response tokens can dominate; no latency speedup is claimed.

| Workflow | Actual observed/current sequence | Desired sequence | Defensible saving |
|---|---|---|---|
| Discover store | Four preparatory tool interactions before create | `where --json`, then ordinary creation | Up to three discovery round trips for that episode; naming help still separate |
| Capture created ID | add → list → grep/awk → comment → sync | add `--ids-only` → comment → sync | One list call and text parsing; entirely current CLI |
| Verify changed description | Current set returns ID/title/status; show then projection needed to inspect desc | Set with proposed resulting-field receipt | One read/process when receipt is sufficient; not an integrity or remote audit |
| Read two issues through Nix | First help/show call's capped output obscured content; second filtered call recovered it | Required environment wrapper with startup output handled separately, then ordinary show | One avoidable recovery interaction in the episode; no claim ditz controls Nix stdout |
| File five descriptions | Shell syntax error → generated-script retry → five successful creates | Literal-input script + five checked creates | One repair interaction; new multi-add engine unnecessary |
| Close mixed IDs | Current one close call already returns successful IDs and errors | Same call, optional richer receipt | No reduction in calls; clearer recovery/state only |

For a concrete synthetic command-only comparison:

```sh
# Current, 94 bytes including newline; ~24 token-equivalents.
ditz set widget-a --desc 'new' --json
ditz show widget-a --json | jq '{id,title,status,desc}'

# PROPOSAL, 48 bytes including newline; ~12 token-equivalents.
ditz set widget-a --desc 'new' --output json-v1
```

The proposed receipt adds metadata bytes but avoids sending the full issue log in
a second `show`. Exact total savings depend on issue history; a tiny issue can make
the richer receipt larger. Stable, truthful composition is the reason to consider
it, not a universal token-saving claim.

## Concrete acceptance scenarios for later implementation

These are future acceptance criteria, **not tests passed by this documentation**.
Use synthetic temporary repositories only; exercise both filesystem and git
backends where the contract applies.

| Scenario | Required evidence |
|---|---|
| Named create, repeated create, mismatched supplied fields | Exactly one issue; original fields retained; current no-op semantics preserved; new receipt identifies created vs existing and mismatches. Unreadable occupant is never overwritten. |
| Literal multi-line description/comment | Quotes, dollar signs and backticks remain literal; command substitution is never evaluated. Document current outer-whitespace trimming rather than promising byte-for-byte stdin preservation. |
| Mixed-ID close | Successful issue closed; missing ID named; exit nonzero; no invented all-or-nothing result. Retrying only failed item does not append to successful item's history. |
| Lost output / repeated lifecycle request | State and log behavior explicitly demonstrated. No exactly-once claim; no unsafe automatic replay of comments. |
| Two independent writers | All successful comments survive and commits contain only owned paths. Configured filesystem issue directory uses the same lock scope as actual storage. |
| Slow input / nested hook | A stalled stdin producer does not monopolize the write lock; nested mutation from a git hook fails promptly with a useful explanation instead of self-deadlocking. |
| Failed commit / rollback | Symlink identity, modes and hard-link policy covered; receipt says effect unknown if restoration cannot be verified. No false success or unrelated staged change committed. |
| Discovery | Worktree, subdirectory, filesystem config, missing local worktree and cached remote-only branch are reported correctly. No files, refs, worktrees or network state change. |
| Strict filter / limit / count | Positive matches included, closed items excluded only when requested, typo never broadens selection, stable limit order, zero limit valid, count untruncated, malformed input errors. |
| Unreadable store during read | Distinguish valid empty set from incomplete/failed scan; match the explicit Q4 policy. |
| Ready / graph | Chain, cycle and dangling endpoint cases; rank/filter before limit. Two readers getting the same ready item is not misrepresented as exclusive assignment. |
| Sync | Missing fetch refspec, offline remote, divergent histories and rejected push: report actual movement and retained local work; cached status explicitly dated by its last sync basis. |
| Compatibility | Existing bare `--json` and `--ids-only` callers continue working; output flags do not silently change mutation semantics; stdin and parser-error paths documented. |

## Product decisions and filing disposition

The decision-maker is the project owner. These are recommendations awaiting
rulings, not compatibility changes smuggled in through documentation.

| Question | Options | Recommendation | Blocks |
|---|---|---|---|
| Q1: versioned mutation result | Keep current receipts + docs; additive opt-in `--output json-v1`; change existing `--json` | Additive opt-in after safety work; approve schema/projection and effect meanings first | Slice 5 |
| Q2: discovery surface | Document git/file recipes only; `where --json`; expand `status` into discovery/repair | Narrow read-only `where`; no repair/automatic initialization | Slice 3 |
| Q3: bounded reads/order | Keep external head/jq; additive limit/count with explicit stable ordering; implicit caps/hide-closed | Additive limit/count; list ID order and ready's already-existing rank/age/ID ordering. Preserve visibility | Slice 4; link existing `decision-hide-closed-limit-count` rather than duplicate it |
| Q4: incomplete read policy | Warning + partial success as now; nonzero structured partial result; fail with no data | Default to nonzero/no selection for a failed scan, with any future partial-read mode explicit. This changes behavior and needs a ruling | Safe selection semantics; separately review compatibility with current consumers |

Other known product questions remain with their existing issues: readable default
IDs/rename, per-agent attribution, onboarding refresh, import-fidelity authorization
and policy, and repository overlap. This sample does not resolve them. It does not
reverse the priority-field decision or authorize migration.

**Filing is explicitly deferred, not claimed complete.** The owner directed this
lane to make no live tracker writes while a separate lead finishes the six existing
PRs. Exact proposed issue payloads and updates are preserved in the private lane
record for the coordinating owner or landing lead to file. New Q1/Q2/Q4 payloads use `open-questions`; Q3 is an
update to the existing decision, with a request to place that existing ruling in `open-questions` rather than
create a duplicate. Actionable documentation/contract findings
are likewise deduplicated there. Existing repo-overlap and import questions are
referenced, never duplicated. Filing belongs to the coordinating owner/landing lead after establishing a safe
write route; no live tracker experiment or edit was performed.

## Validation and stopping point

The baseline binary was built with `nix develop --command dune build bin/main.exe`.
A private synthetic git repository with no remote was used to characterize named
creation/no-op, literal stdin, set/comment/show JSON, partial multi-ID closure,
repeated closure/start, invalid status filters, missing limit/help, dependencies
and ready. A supplemental malformed-member scan checked whether valid results
remain visible while an unreadable issue is skipped. Baseline observations include:

- set JSON omits the changed description; comment JSON returns ID/boolean;
- mixed close returns exit 1 with both successes and errors;
- repeated close succeeds and records another close event;
- `list --status open --json` warns but returns closed issues and exit 0;
- `list --limit` and `ditz help` exit 124;
- `deps` and ready reflect a synthetic blocking edge correctly;
- a malformed fourth issue is warned about and omitted while list returns three
  valid issues with exit 0, motivating Q4 rather than treating partial data as empty.

These probes characterize source `83dd20e`; they do not test the proposed API,
the existing PR heads, concurrency safety or remote sync. The full implementation test suite
was not needed for a documentation-only change. Validation of this report comprises
source/PR reconciliation, evidence-count reconciliation, example-size checks,
Markdown/link/whitespace checks and a complete private-data review of the diff.
No implementation, merge, release, migration, Actions change or remote tracker
mutation belongs to this lane. The next step is product triage and safe tracker
filing; the investigative lane is idle once its report branch and draft PR are
preserved.
