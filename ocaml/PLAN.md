# ditz OCaml Rewrite Plan

## Philosophy

Keep it simple. The original ditz was ~2200 lines of Ruby. We should be able to match functionality in ~1000 lines of OCaml. No sqlite, no daemons, no sync complexity. Just YAML files in a directory that you commit with git.

The killer feature for the AI era: agents can read and write issues as plain text files.

## Mission (revised 2026-06-11): replace beads

The rewrite (Phases 1, 5, 6) substantially shipped (`edit` and the
release-management commands remain) and ditz tracks its own issues. The goal now is
sharper than "rewrite ditz": **be a drop-in replacement for beads in tedks' real
workflows**, with none of beads' daemon/sqlite/sync complexity.

Evidence base: analysis of every `bd` invocation in the Claude and Codex session
histories on this machine (2026-06-11). The observed workflows, by frequency:

1. The agent loop: `bd ready --json` → `bd update X --status in_progress` → work →
   `bd close X --reason "..."` (dominant pattern in both histories)
2. Typed creation: `bd create "title" -t task --priority 1 [--parent epic] [--json]`
   (`-t` on ~84% of creates, `--priority` ~40%, `--parent` ~19%)
3. `--reason` on 54–87% of closes
4. JSON-everything piped to jq
5. Constant `bd sync`
6. `bd init --branch beads-metadata --prefix <proj>` → short IDs (`proj-42`) used in
   every subsequent command
7. Secondary: `comment`, `dep add`/`dep tree`/`graph`, `show --children`, `q`,
   `list --parent/--label/--assignee/--limit`, `status`, `search`, `reopen`

Explicitly NOT chasing: beads' daemon, `mol`/wisp/gate/swarm orchestration (Gas Town
stays on beads), sqlite, merge drivers. ditz's answer to "sync complexity" is
files + git, not a better daemon.

### Definition of production-ready

1. **Zero-config**: identity falls back to `git config user.name/email`;
   `ditz init && ditz add "x"` works on a fresh machine with no `~/.ditz-config`.
2. **Mission parity, the ditz way** (re-scoped 2026-06-14, see Phase 7):
   cat-able/greppable scalar YAML, one-shot typed creation, status as data
   (`reopen`, `close --reason`, `set --status`), graph-derived `ready`
   ordering, `count`/`--limit`, JSON everywhere. NOT a stored priority field,
   parent/epic field, ID scheme, or dep-graph renderer — each was a
   beads-shaped answer to a problem we don't have (Phase 7 records why).
3. **No known data-loss paths**: atomic writes on both backends, conflict-safe sync.
4. **CI green on every PR** (DONE — PR #6; nix-cached ~5-min runs).
5. **One real project migrated off beads**: predictionbook, used daily by agents
   for a week without manual repair, gates 0.1.0; goals migrates after the tag.

### Roadmap (sequenced)

Each step is roughly one focused session; steps 1–2 can be a stacked-PR chain.

- **Step 0 — Unblockers**: merge PR #4 (worktree root detection — including the
  bare-at-root container fix, worktree ownership check, and cwd-independent
  listing from the 2026-06-11 council review); identity fallback to git config
  (PR #7 — kills the init↔config chicken-and-egg AND the "Test User" data
  pollution); CI via the nix flake (PR #6, merged). Everything later writes
  issue data and lands PRs, so identity + CI come first.
- **Step 1 — Data safety** (Phase 8.2–8.3, then 8.7): atomic git-backend writes,
  read leak, epoch fallback, then sync conflict auto-resolution, THEN tracker
  cleanup (purge `issue-abc123`/`abc999` test artifacts, re-file the 3
  unparseable hand-written phase issues, close the 2 already-fixed review
  issues) — cleanup rewrites live tracker data, so it waits for the trustworthy
  write path. Before parity work pulls more usage (and before migration imports
  real data) the write path must be trustworthy.
- Step ownership, to keep sessions from colliding: 7.1, 8.1, 8.4 done in
  Steps 0–1; 8.5 rode with CI; 8.6 type-debt folds into 7.0.
- **Step 2 — ditz-native core** (Phase 7.0, 7.2, 7.3): clean scalar YAML FIRST
  (the foundation and the primary documentation mechanism), then status-as-data
  (`reopen`, `close --reason`, `set --status`) and one-shot typed creation.
  Land the Tier-1 documentation (errors-name-the-remedy, empty-state redirects)
  alongside, since the commands are already open.
- **Step 3 — polish & self-documentation** (Phase 7.4, 7.5 + docs tiers 2–3):
  graph-derived `ready` ordering, `count`/`--limit`, clone onboarding, `FORMAT.md`,
  and `init` writing the agent snippet into `AGENTS.md`. Fittingly, most of this
  step is documentation: when the file is the interface, the format doc is the
  product.
- **Step 4 — Migration & rollout** (Phase 9): `ditz import beads`, distribution to
  all machines, migrate predictionbook and run it for a week (this gates the tag).
- **Step 5 — Tag 0.1.0**, then migrate goals and retire both projects' beads
  daemons. Everything else (HTML export, Ruby compat beyond read-tolerance,
  `doctor`, `stale`) stays in the backlog until it earns its place.

## Current State

- [x] Project scaffolding (dune, opam deps)
- [x] Core types with YAML serialization
- [x] Basic storage layer (load/save YAML files)
- [x] CLI skeleton with cmdliner
- [x] `init` command (creates .ditz directory)
- [x] `list` command (shows all issues)
- [x] `add` command (creates issue with title)
- [x] `show` command (display full issue details)
- [x] `start` command (mark issue in_progress)
- [x] `stop` command (mark issue paused)
- [x] `close` command (close with disposition)
- [x] `drop` command (delete an issue)
- [x] Dependency tracking fields (blocks, blocked_by)
- [x] File reference fields (file_refs)
- [x] `--json` flag on all commands
- [x] `--ids-only` flag for quiet output
- [x] `context` command (dump all open issues for LLM context)
- [x] `ready` command (show issues ready to work on)
- [x] Batch operations (`close`, `start`, `stop` accept multiple IDs)
- [x] `comment` command (add comments to issues)
- [x] Idempotent creates (`--id` flag)
- [x] Stdin support (`--desc-stdin`, `--stdin`)
- [x] List filtering (`--type`, `--component`, `--status`)
- [x] `blocks` / `unblocks` commands (dependency management)
- [x] `ref` command (add file references)
- [x] `set` command (update issue fields)
- [x] `search` command (full-text search)
- [x] `assign` / `unassign` commands (release management)
- [x] `status` command (project overview)

## Phase 1: Core Commands

### Issue Lifecycle
- [x] `show <id>` - Display full issue details
- [x] `start <id>` - Mark issue in_progress
- [x] `stop <id>` - Mark issue paused
- [x] `close <id> [--fixed|--wontfix|--reorg]` - Close with disposition
- [x] `drop <id>` - Delete an issue

### Issue Modification
- [ ] `edit <id>` - Open issue in $EDITOR
- [x] `comment <id>` - Add comment to log
- [x] `assign <id> <release>` - Assign to release
- [x] `unassign <id>` - Remove from release
- [x] `set <id>` - Change issue fields (type, component, title, desc)
- [x] `ref <id> <path>` - Add file reference
- [x] `blocks <a> <b>` - Mark dependency relationship
- [x] `unblocks <a> <b>` - Remove dependency relationship
- [x] `search <query>` - Full-text search across issues

### Project Management
- [x] `status` - Overview of project state
- [ ] `add-release <name>` - Create new release
- [ ] `release <name>` - Mark release as shipped
- [ ] `add-component <name>` - Create new component

## Phase 2: Compatibility

> **DESCOPED 2026-06-11.** Read-tolerance only: never crash on Ruby-ditz or
> unknown-field YAML; skip with a warning (already the behavior). No write-back of
> Ruby format. The field-mapping table below stays as reference for the beads/Ruby
> importers (Phase 9.1). Issue naming is superseded by prefixed IDs (Phase 7.2).

### YAML Format
The original Ruby ditz uses a YAML tag: `!ditz.rubyforge.org,2008-03-06/issue`

Options:
1. **Ignore tags** - Parse as plain YAML, ignore the Ruby-specific tag
2. **Support both** - Read old format, write new format
3. **Migration tool** - One-time conversion script

Recommendation: Option 1 for reading (the yaml library should handle this), write clean YAML without tags.

### Field Mapping
| Ruby field | OCaml field | Notes |
|------------|-------------|-------|
| `type` | `issue_type` | Reserved word in OCaml |
| `log_events` | `log_events` | Array of [time, who, what, comment] |
| `creation_time` | `creation_time` | Ruby Time -> ISO8601 string |

### Issue Naming
Original ditz assigns human-readable names like `#1`, `#2` or `component-1`, `component-2`. We need to implement `assign_issue_names!` logic.

## Phase 3: User Experience

> **MOSTLY CUT 2026-06-11.** Interactive prompts are an anti-goal — the primary
> users are agents (and a human who pipes). Status widgets already shipped. Color
> and pagination stay in the backlog. Config commands are superseded by the
> git-identity fallback (Phase 7.1).

### Interactive Mode
- [ ] Interactive prompts for issue creation (type, component, release)
- [ ] Multi-line description input via $EDITOR
- [ ] Confirmation prompts for destructive operations

### Output Formatting
- [ ] Color output (already have fmt)
- [ ] Status widgets: `_` unstarted, `>` in_progress, `=` paused, `x` closed
- [ ] Grouping by type (bugs, features, tasks)
- [ ] Pagination for long lists

### Config
- [ ] `~/.ditz-config` for user name/email
- [ ] Per-project `.ditz-config` override
- [ ] `ditz reconfigure` command

## Phase 4: Nice-to-Haves

> **BACKLOG 2026-06-11.** Nothing here blocks beads replacement. Revisit after 0.1.0.

### Plugins (maybe)
The Ruby version had a plugin system. Consider:
- [ ] Git integration (show branch for issue)
- [ ] Hooks (pre/post commands)

### Views
- [ ] HTML generation (the Ruby version has this)
- [ ] Markdown export
- [ ] JSON output for scripting

## Phase 5: AI Agent Experience

This is the actual killer feature. What would make an AI agent *love* using this?

### My Frustrations with Beads

1. **Dual persistence complexity** - SQLite + JSONL means sync bugs, merge driver pain, worktree redirect files. When it breaks, it's confusing.
2. **Opaque state** - I can't just `cat` an issue. I have to query.
3. **Verbose output** - Sometimes I just want the ID back, not a paragraph.
4. **No batch operations** - Closing 5 issues = 5 commands.
5. **Daemon brittleness** - "Is the daemon running? On which worktree? What port?"

### What I Actually Want

#### 1. One File = One Issue (already have this!)
The `.ditz/issue-{id}.yaml` pattern is perfect. I can:
- `cat` it directly
- `grep` across all issues
- Parse it myself if the CLI is weird
- Edit it with any tool

#### 2. `--json` Flag on Everything
Every command should support `--json` for structured output I can parse:
```bash
ditz add "Fix the thing" --json
# {"id": "abc123", "title": "Fix the thing", "status": "unstarted"}

ditz list --json
# [{"id": "abc123", ...}, {"id": "def456", ...}]
```

#### 3. Context Dump
A single command that gives me everything I need to understand the project:
```bash
ditz context
# Dumps: project info, all open issues, recent activity
# In a format optimized for putting in an LLM context window
```

Maybe even `ditz context --issue abc123` that includes related issues, blockers, etc.

#### 4. Dependency Tracking
Simple `blocks` / `blocked-by` relationships:
```bash
ditz blocks abc123 def456    # abc123 blocks def456
ditz unblocks abc123 def456
ditz show abc123             # Shows: "Blocks: def456, ghi789"
```

I discover dependencies constantly while working. Being able to record them is huge.

#### 5. File References
Link issues to specific files/locations:
```bash
ditz ref abc123 src/auth.ml:42
ditz show abc123
# References:
#   - src/auth.ml:42
```

When I'm fixing an issue, I know *exactly* where the problem is. Record that.

#### 6. Batch Operations
```bash
ditz close abc123 def456 ghi789 --fixed
ditz start $(ditz list --unstarted --ids-only | head -3)
```

#### 7. Idempotent Creates
```bash
ditz add "Fix the thing" --id fix-auth-bug
ditz add "Fix the thing" --id fix-auth-bug  # No-op or update, not error
```

Deterministic IDs mean I can retry without creating duplicates.

#### 8. Stdin for Descriptions
```bash
echo "Detailed description here" | ditz add "Title" --desc-stdin
cat error.log | ditz comment abc123 --stdin
```

I'm generating content. Let me pipe it.

#### 9. Template Support
```bash
ditz add --template bug "Login fails on Firefox"
# Pre-fills: type=bugfix, prompts for component, etc.
```

#### 10. The `ready` Command
```bash
ditz ready
# Lists issues that are:
#   - Unstarted or paused
#   - Not blocked by anything
#   - Assigned to current release (or unassigned)
# i.e., "What can I work on right now?"
```

This is what I actually need when starting work.

### Output Modes

Three modes for every command:
1. **Human** (default) - Pretty, colored, readable
2. **JSON** (`--json`) - Structured, parseable
3. **Quiet** (`-q`) - Just IDs or exit codes

```bash
ditz add "Fix thing"           # "Created issue abc123: Fix thing"
ditz add "Fix thing" --json    # {"id":"abc123","title":"Fix thing",...}
ditz add "Fix thing" -q        # abc123
```

### Non-Interactive by Default

Unlike Ruby ditz which prompts for everything, default to non-interactive:
```bash
ditz add "Fix thing"                    # Creates with defaults
ditz add "Fix thing" --interactive      # Prompts for type, component, etc.
ditz add "Fix thing" --type bug --component auth  # Explicit
```

I'm an AI. I know what I want. Don't make me answer questions.

## Phase 6: Git Integration & Worktrees

### The ditz-metadata Branch

Issue data lives in a separate orphan branch, not in your feature branches. This is the beads-metadata pattern, but simpler.

**Why:**
- No merge conflicts between code and issues
- Issues don't pollute your PR diffs
- One canonical location for issue state
- Works naturally with worktrees

**How it works:**
```
main              feature-branch        ditz-metadata
  │                    │                     │
  │                    │                 .ditz/
  │                    │                 ├── project.yaml
  │                    │                 ├── issue-abc.yaml
  │                    │                 └── issue-def.yaml
```

Every ditz command:
1. Checks out ditz-metadata to a temp location (or uses sparse checkout)
2. Reads/writes issue files
3. Commits changes
4. Optionally pushes

### Worktree Support (First-Class)

Multiple worktrees, one issue database. No redirect files, no confusion.

```bash
# Main checkout
~/projects/myapp/           # main branch
~/projects/myapp-feature/   # feature branch (worktree)
~/projects/myapp-hotfix/    # hotfix branch (worktree)

# All three share the same ditz-metadata branch
ditz list  # Same output in any worktree
```

**Implementation:**
- `ditz init` creates the ditz-metadata branch
- All ditz commands find the git root and operate on ditz-metadata
- No .ditz directory in working tree at all (it's in the branch)

### The Sync Command

```bash
ditz sync
# 1. Fetches origin/ditz-metadata
# 2. Merges (trivial because of file-per-issue)
# 3. Pushes ditz-metadata
```

This is the only command that touches the network. Everything else is local.

### Making Conflicts Trivial

**One file per issue** - already have this. Conflicts only happen if two people edit the same issue simultaneously.

**Append-only log events** - The `log_events` field is append-only. If two people add comments, both comments should appear. Conflict resolution: concatenate and sort by timestamp.

**Last-write-wins for status** - If two people change status, the later timestamp wins. Simple.

**Deterministic field order** - YAML fields always written in the same order. Reduces spurious diffs.

**No derived state** - Don't store computed values (like issue counts). Derive them at read time.

### Conflict Resolution Strategy

When `ditz sync` hits a conflict:

```bash
ditz sync
# CONFLICT in issue-abc123.yaml
# Auto-resolving...
#   - Merged log_events (2 + 1 = 3 entries)
#   - Status conflict: took later timestamp (in_progress)
#   - References: union of both sides
# Resolved. Continuing sync.
```

Most conflicts auto-resolve. For the rare case they don't:
```bash
ditz sync
# CONFLICT in issue-abc123.yaml
# Could not auto-resolve: both sides changed title
# Left in .ditz-conflict/issue-abc123.yaml.{LOCAL,REMOTE}
# Run: ditz resolve abc123
```

### Commands

```bash
ditz init                    # Create ditz-metadata branch
ditz sync                    # Fetch, merge, push
ditz sync --pull-only        # Just fetch and merge
ditz sync --push-only        # Just push

# These all work transparently with the branch:
ditz add "Fix thing"         # Commits to ditz-metadata
ditz close abc123            # Commits to ditz-metadata
ditz list                    # Reads from ditz-metadata
```

### Auto-Sync Option

For convenience, auto-sync after every write:
```bash
ditz config set auto-sync true
ditz add "Fix thing"         # Also runs sync
```

But off by default. Explicit is better.

### Implementation Notes

Use `git worktree add --detach` or sparse checkout to access ditz-metadata without disturbing the working tree. The user never sees a .ditz directory.

```bash
# Pseudocode for every ditz command:
temp_dir = mktemp()
git worktree add --detach $temp_dir ditz-metadata
# ... do work in $temp_dir/.ditz/ ...
git -C $temp_dir add -A
git -C $temp_dir commit -m "ditz: $command"
git worktree remove $temp_dir
```

Or use git's index directly without a worktree checkout (faster, more complex).

> **SUPERSEDED 2026-06-11.** The pseudocode above describes the original
> ephemeral per-command worktree. What shipped (c05f559) is a persistent sparse
> worktree at `<container>/.ditz-worktree`, reused across commands
> (`DITZ_EPHEMERAL_WORKTREE=1` keeps the old behavior). Don't re-implement the
> pseudocode.

## Phase 7: ditz-native core (re-scoped 2026-06-14)

Re-scoped from "match beads feature-for-feature" to "serve the mission the
ditz way." The mission (Philosophy + Phase 5): **agents read and write issues
as plain text files; git is the database; no derived state is stored; the file
is the interface.** Held against that, several planned features turned out to be
beads-shaped solutions to beads-shaped problems we don't have.

### What we cut, and why

- **dep tree / `graph` renderer — CUT.** Beads needs a tree *viewer* because
  sqlite hides the data — you can't see a relationship without querying the
  daemon. Our graph is already plain text: `blocks:` / `blocked_by:` lines you
  can `grep`, walk with `--json | jq`, or dump with `context` and let the LLM
  reader understand the structure. A renderer is a human convenience, not a
  mission need.
- **Prefixed / sequential / random IDs — CUT.** Stripped of muscle memory, an
  identifier needs only two things: a stable cross-reference handle and
  coordination-free, collision-safe minting. We have both today — but note the
  mechanism precisely (council C1): `make_id` is a SHA1 of
  `time+random+content`, NOT content-addressed, so the same title yields a
  different ID each call. Stability comes from the ID being **written once and
  then immutable**; collision-safety from the time+random entropy plus a
  local-tree check; `--id custom` covers deterministic/human handles (and
  idempotent creates depend on it — don't "simplify" `make_id` to a pure
  content hash, that reintroduces cross-clone collisions). Prefix-matching
  makes IDs short to type — the *git idiom* (nobody types full commit hashes).
  The `proj-` prefix solved a beads problem: beads DBs span projects/rigs and
  need namespacing; our tracker is per-repo, so **the repo IS the namespace.**
  Known edge (document, don't fix): a short prefix unique in clone A can go
  ambiguous in clone B after a sync — `find_issue_by_id` already errors with the
  candidate list rather than guessing, the same way git handles a grown hash
  space. Cutting this retires the one design question two council rounds
  couldn't settle — the tell it was the wrong question.
- **parent / epic field — CUT.** Belonging is expressed by `component`
  (`list --component`); sequencing by `blocks`/`blocked_by`. An "epic" is an
  issue `blocked_by` its members — `ready` already hides it until they close.
  Two honest limits to document (council I1), not paper over: (a) `component`
  is a SINGLE string, so an issue lives in one grouping axis only —
  multi-membership ("auth epic AND backend component") is out of scope; (b)
  epic-as-`blocked_by` is a *sequencing* claim, so it skews 7.4's unblock-count
  (every member appears to "unblock" the epic). Therefore: use the blocks
  encoding only for epics whose members are genuinely sequenced; for pure
  grouping-only epics, use a shared `component` and NO graph edge. Document the
  pattern (Phase 9.3).
- **Stored `priority` field — CONTESTED (operator decision pending).** Original
  call: cut it, derive urgency from the graph at read time (7.4). **All three
  council reviewers pushed back**, and the objection is sound: a human/agent
  asserting "this is urgent" is *input* state, not *derived* state — so the
  "no derived state" principle does NOT argue against a priority field (it's
  the unblock-count that's derived). The real argument for cutting is staleness,
  which is a bet, not a law. The concrete failure mode: on a flat or
  lightly-linked graph (ditz's own tracker today), unblock-count is constant
  and ordering collapses to age-only, which *buries a small-but-urgent leaf*
  (a prod incident, a security fix, an external commitment that blocks nothing)
  under a low-value hub. See 7.4 for the pending decision and options.

### 7.0 Clean scalar YAML — THE foundation
The ppx_deriving_yaml output (`status:\n  Unstarted: []`) breaks the founding
philosophy — issues should be cat-able and greppable. Write plain scalars
(`status: unstarted`, `type: feature`) via custom to_yaml/of_yaml; keep reading
the variant-map format for existing files (one-time rewrite on next save).
This is not just integrity — it is the **primary documentation mechanism**: when
the file reads `status: unstarted`, the data is self-describing and an agent
learns the whole schema by `cat`-ing one issue. `grep "status: closed"` becomes
literally true. Do this FIRST: every other change adds fields, and they should
land in the stable, self-documenting representation. (8.6 type-debt folds in
here, since the type files are open anyway.)

### 7.1 Identity without config — DONE (PR #7)
Reporter resolves `~/.ditz-config` → `$DITZ_USER`/`$DITZ_EMAIL` → `git config`
→ fix-it error. Remaining: `init` derives project name from `basename(cwd)`,
which yields "master" in worktree layouts — add `init --name`, default to the
common-root basename.

### 7.2 Status as data
`closed` is currently a dead-end state (`start_issue` refuses it, issue_ops.ml)
and close events can't carry their why — data-model holes independent of beads.
- [ ] `reopen <id>` (closed → unstarted, logged)
- [ ] `close --reason TEXT` → logged as the close event comment
- [ ] `set --status unstarted|in_progress|paused` — one verb for the common
      mutation; `start`/`stop`/`close` stay as sugar. `set` already exists.

### 7.3 One-shot creation
Completes ditz's own non-interactive principle (Phase 5: "I'm an AI. I know
what I want. Don't make me answer questions."), and one command = one commit =
cleaner metadata history than add-then-set.
- [ ] `add -t|--type`, `-c|--component`, `--desc TEXT` (alongside `--desc-stdin`)

### 7.4 `ready` ordering
Derivation mechanics, required regardless of the priority decision (council C2 —
none of this exists today; `ready` is a bare filter with no sort):
- [ ] Score = count of currently-OPEN issues each transitively unblocks, over
      the `blocked_by` edges. Closed issues contribute nothing.
- [ ] Cycle-safe: nothing prevents cycles in `blocks`/`blocked_by` today (the
      ops are list-appends with no check, and a hand-edited/merged file can be
      one-sided), so the walk MUST be a memoized DFS with a visited-set — a
      naive recursion will not terminate. Single memoized post-order pass
      (O(V+E)), not per-node re-walk.
- [ ] Tiebreak: ascending `creation_time` (lexicographic RFC3339), then `id`
      for total stability. NOTE: load order is NOT age — FS `readdir` is
      OS-arbitrary and git `ls-tree` is by id; the sort key must be the
      `creation_time` field explicitly.
- [ ] Flat-graph degeneration (state it plainly): with few/no deps, every score
      is 0 and ordering collapses to oldest-first. That is the heuristic's blind
      spot for urgent-but-unblocking work (see the priority debate above).

**Pending operator decision — primary sort key:**
- Option A (original): pure derivation — score, then creation_time. No stored field.
- Option B (council consensus): optional `priority` input (unset by default) as
  the PRIMARY key when set, score as the tiebreaker, creation_time last. Keeps
  the derivation insight (it still orders everything unset and breaks ties) AND
  lets an agent flag the urgent leaf the graph can't see. Re-adds one stored
  field — but it is *input*, not derived, so it doesn't violate the principle.
  Beads import (9.1) would then preserve priority instead of dropping it.

### 7.5 count / list --limit
- [ ] `count` (same filters as `list`), `list --limit N`. These name the
      `... | jq length` and `... | head` idioms as discoverable affordances —
      a small but real form of structural documentation (see below).

### Documentation model (agent-first, three tiers)

Governing principle: **agents don't leave the loop to read docs; they read
what's already in context — tool output and error messages.** Rank by proximity
to the feedback loop, not by preference.

**Tier 1 — baked into output, at the two moments an agent is actually reading:**
- [ ] Errors name the remedy: closed→`reopen`, ambiguous-id→list candidates
      (done), no-tracker→`ditz init`. The agent is blocked and reading — the
      one moment a hint is guaranteed consumed.
- [ ] Empty-states redirect: `ready` empty→"N blocked"; `list` empty→"`ditz
      add`". Silence makes an agent guess.
- [ ] HARD RULE: never in `--json` (breaks the jq pipe → trains distrust of
      `--json`), never in `-q`, never as happy-path success-noise (banner
      blindness + token waste). Surprise and stuck, only.

**Tier 2 — structural (the CLI shape is the doc):**
- [ ] Symmetry: ship `reopen` partly *because* it is the visible inverse of
      `close`; `--json`/`-q` on every command so learning it once licenses
      assuming it everywhere.
- [ ] `--help` examples are the loop (`ready → start → close --reason`) and one
      jq idiom, not a flag dump.
- [ ] 7.0 scalar YAML: the issue files ARE the schema doc (learned by example,
      zero extra tokens, always present).

**Tier 3 — pull docs (for the human and the first-contact agent):**
- [ ] `FORMAT.md`: one-issue-one-file, the YAML schema, the git-branch model.
      When the file is the interface, this is the product manual.
- [ ] Onboarding snippet delivered agent-first: **`ditz init` writes it into the
      repo's `AGENTS.md`/`CLAUDE.md`** — the ditz-native `bd onboard`, landing
      in the file agents already read on arrival, travelling with the project
      via git, no daemon, no command to remember.
- [ ] CLOBBER SAFETY (council I3, all three reviewers — the most concrete gap):
      these files are policy-bearing and, in tedks' setup, often SYMLINKS to a
      canonical instruction file. So `init` must: append only, between sentinel
      markers (`<!-- ditz:onboard -->`…`<!-- /ditz:onboard -->`); never
      overwrite; be idempotent (skip if the markers are already present);
      **refuse to follow a symlink** (write through one and it corrupts the
      shared canonical file for every project). Absent the file, create it;
      otherwise inject the block. Re-`init` must be a no-op.
- [ ] NOT a `ditz guide` command (a pull an agent won't think to make) and NOT
      an operating-preamble inside `context` (run repeatedly to load state — a
      fixed manual per call is pure token waste).

### Backlog (not blocking 0.1.0)
- `init --branch NAME` (un-hardcode `ditz-metadata`) — no mission driver while
  the tracker is per-repo.
- `labels` / `assignee` fields — nothing in the mission wants them; the
  assignee-heavy usage in the histories was Gas Town rigs (a non-goal).

## Phase 8: Production Hardening

### 8.1 Land PR #4 — DONE
Worktree/root detection fix — required for bare-repo + worktree layouts (i.e. how
tedks actually uses git). Council review (2026-06-11) found and fixed in-PR: the
bare-at-root container derivation (silent cross-project writes), the worktree
ownership check, stale-registration self-heal, init-from-bare-root crash, and
cwd-dependent empty `list` from subdirectories. Smoke test done on the real layout.

### 8.2 Write-path integrity — DONE (PR #8)
- [x] Git backend writes through the same temp-file + rename helper as FS backend
      (shared `Fs_util.write_file_atomic`; atomic + symlink-safe)
- [x] `read_yaml_file` closes channel on exception (`Fs_util.read_file`, Fun.protect)
- [x] `now_rfc3339` raises instead of silently returning epoch (issue_ops.ml)

### 8.3 Sync conflict auto-resolution — DONE (PR #9)
Pure `Merge` module over git index stages: log_events union (time-sorted),
status+disposition three-way-picked-then-LWW, no-resurrection list merges,
hard-conflict on double-changed scalars → abort + `.ditz-conflict/` LOCAL/REMOTE
escape hatch. IDs stay content-SHA1 (7.2 cut); the only same-path conflict class
is two edits of one issue, which this covers. Resolution emits parseable YAML.

### 8.4 CI — DONE (PR #6)
GitHub Actions, nix-based `dune build` + `dune runtest` on every PR, `/nix/store`
cached (~5-min warm runs). Backlog nits (filed): `concurrency` group, job timeout.

### 8.5 Test isolation — DONE
Tests scrub `$HOME`/`GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` (config_test) and use
temp repos; new writes no longer carry the "Test User" reporter.

### 8.6 Type-level debt — folds into 7.0
.mli interfaces, typed error variants (replace polymorphic `` `Msg ``), illegal
states unrepresentable (status × disposition). Do it during the 7.0 scalar-YAML
rewrite, when the type files are already open — not as standalone churn.

### 8.7 Tracker cleanup — DONE
Purged `issue-abc123`/`abc999`; re-filed the 3 old-format phase issues in tool
format and closed them; closed the review issues fixed by PRs #4/#8. `ditz list`
runs warning-free; tracker synced.

## Phase 9: Migration & Rollout

### 9.1 Beads import — in OCaml, deliberately
- [ ] `ditz import beads <issues.jsonl>` (from `bd export` or `.beads/issues.jsonl`)
- [ ] Mapping: open→unstarted, in_progress→in_progress, blocked→(dep-derived),
      closed→closed+fixed; deps→blocks/blocked_by; parent→`blocked_by` (epics are
      blocks, Phase 7); comments→log_events; beads id kept as the ditz id via
      `--id` (idempotent re-import). `priority` → depends on the 7.4 decision:
      DROPPED under Option A, preserved under Option B (the council noted dropping
      it is lossy — ~40% of beads creates set it).
- [ ] Partial-graph imports: a beads `blocked` issue whose blockers aren't in
      the export must still land as `unstarted` with whatever `blocked_by` edges
      ARE present (don't invent a `Blocked` status — ditz derives blocked-ness);
      warn on dangling edge targets rather than failing the import.
- Why OCaml and not a contrib script, re Philosophy "Parse it myself if the CLI
  is weird": that line protects DAILY read access — never being locked out of
  your own issues when the tool misbehaves — and import doesn't spend it (issues
  remain plain files afterward). Import is one-shot, lossy-if-wrong data
  migration; it wants the type model's validation, status/event mapping, and
  `--id` idempotency, which a jq script reimplements badly. Keep the beads-schema
  half tolerant and isolated (beads' JSONL is the unstable external thing); our
  types are the stable half.

### 9.2 Distribution
- [ ] `nix build` produces the single binary; install on all machines (PATH),
      pinned via dotfiles. An agent can't adopt a tool that isn't installed.

### 9.3 Agent onboarding — delivered agent-first
- [ ] `ditz init` writes the snippet (ready→start→close loop, `--json` flags, id
      conventions, the epic=blocks and component=grouping patterns) into the
      repo's `AGENTS.md`/`CLAUDE.md` — see Phase 7's documentation model. Lands
      in the file agents already read; travels with the project via git.
- [ ] `FORMAT.md` (the schema/branch-model manual) committed to this repo.
- [ ] Update any skills/docs that hardcode beads for migrated projects.

### 9.4 Migrate real projects
- [ ] predictionbook first (lower stakes), verify a week of daily agent use —
      this gates the 0.1.0 tag (DoD #5)
- [ ] goals AFTER the tag; stop each project's beads daemon as it migrates
- [ ] this repo's tracker is already ditz (dogfooding since January)

### 9.5 Tag 0.1.0 with changelog

## Non-Goals

Things we're explicitly NOT doing:
- No sqlite (files only)
- No daemon process
- No complex merge driver (auto-resolve or bail)
- No external service integration (no JIRA bridge)
- No web UI server
- No beads `mol`/wisp/gate/swarm/merge-slot orchestration layer — that's Gas Town's
  domain and it keeps beads; ditz replaces beads for plain project tracking
- No `bd`-named CLI shim — parity is conceptual (same fields/flags/loop), agents
  get retrained via the onboarding snippet (Phase 9.3), not via command aliasing
- No dep-tree / `graph` renderer — the graph is already plain text in the files
  (`grep`, `jq`, `context`); a viewer exists only because sqlite hid the data (Phase 7)
- No ID scheme beyond content-SHA1 + prefix-matching + `--id` — the repo is the
  namespace, so prefixed/sequential/random IDs solve a problem we don't have (Phase 7)
- No `parent`/`epic` field — `component` is grouping, `blocks` is sequencing; an
  epic is an issue blocked by its members (Phase 7)
- No stored *derived* state (issue counts, cached graph rollups) — derive at
  read time. (A stored `priority` is *input*, not derived, so it is NOT covered
  by this — its fate is the open 7.4 decision, not a non-goal.)

## Architecture

```
lib/
├── types.ml      # Domain types (Issue, Project, etc.)
├── storage.ml    # YAML file I/O
├── project.ml    # Project operations (add issue, etc.)
├── commands.ml   # Command implementations
└── ditz.ml       # Library entry point

bin/
└── main.ml       # CLI with cmdliner
```

## Testing Strategy

- Unit tests for type serialization (round-trip YAML)
- Unit tests for project operations
- Integration tests: init, add, list, show, close flow
- Compatibility test: load original Ruby ditz issues

## Build & Release

```bash
# Development
nix develop
opam install . --deps-only
dune build

# Release
dune build @install
# Produces single binary: _build/default/bin/main.exe
```

Target: single static binary that can be dropped anywhere.

## Open Questions

1. **Issue ID format**: ~~Keep SHA1 hashes or switch to shorter IDs?~~
   **RESOLVED 2026-06-11**: prefixed short RANDOM (`proj-a3f2k`, Phase 7.2).
   Short + prefixed is what the beads muscle memory actually values;
   sequentiality was rejected by council review (concurrent same-clone minting
   races, renumber-on-sync re-pointing live references). SHA1 and `--id custom`
   remain accepted.

2. **Config location**: ~~`~/.ditz-config` or `~/.config/ditz/config.yaml`?~~
   **RESOLVED 2026-06-11**: mostly moot — identity comes from `git config` with
   `~/.ditz-config` as an optional override (Phase 7.1). Beads needs zero identity
   config and so should we.

3. **Backward compat**: How much effort to spend on reading Ruby ditz repos?
   - Leaning: Best-effort. Parse the YAML, ignore the Ruby tags.
   - Don't crash on unknown fields.

4. **Name**: Keep "ditz" or rename?
   - Leaning: Keep "ditz". It's short, memorable, and pays respect to the original.

5. **Dependency storage**: Inline in issue YAML or separate index?
   - Leaning: Inline. `blocks: [id1, id2]` and `blocked_by: [id3]` fields.
   - Denormalized but simple. Validate on load.

6. **File references**: Just paths or structured?
   - Leaning: Structured. `{path: "src/foo.ml", line: 42, note: "the bug is here"}`
   - But accept simple "path:line" syntax on CLI.
