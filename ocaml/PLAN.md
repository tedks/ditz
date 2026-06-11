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
2. **Parity for the observed 90%**: typed/prioritized creation, generic status
   update, close-with-reason, ready loop, short prefixed IDs, parent/epic,
   deps + tree view, comments, JSON everywhere.
3. **No known data-loss paths**: atomic writes on both backends, conflict-safe sync.
4. **CI green on every PR** (currently there is no CI at all).
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
- Step ownership, to keep sessions from colliding: 7.1, 8.1, 8.4 execute in
  Step 0; 8.7 in Step 1; 8.5 rides with 8.4's CI; 8.6 folds into Step 2's type
  changes. Step 2 then covers 7.0 and 7.2–7.7.
- **Step 2 — Parity core** (Phase 7.0–7.7): clean YAML scalars; creation flags +
  priority field + `close --reason` + `set --status`; prefixed short IDs;
  parent/epic. This is ~90% of the observed muscle memory.
- **Step 3 — Agent-loop polish** (Phase 7.8–7.11): `dep tree`, `reopen`, `count`,
  `list --limit`, priority-sorted `ready`; labels/assignee if wanted.
- **Step 4 — Migration & rollout** (Phase 9): beads JSONL import, distribution to
  all machines, agent onboarding doc, migrate predictionbook → goals, retire their
  beads daemons.
- **Step 5 — Tag 0.1.0**. Everything else (HTML export, Ruby compat beyond
  read-tolerance, `doctor`, `stale`) stays in the backlog until it earns its place.

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

## Phase 7: Beads Parity

Ordered by observed usage frequency. 7.0–7.7 are the "90% of muscle memory" tier.

### 7.0 Clean scalar YAML
The ppx_deriving_yaml output (`status:\n  Unstarted: []`) breaks the founding
philosophy — issues should be cat-able and greppable. Write plain scalars
(`status: unstarted`, `type: feature`) via custom to_yaml/of_yaml; keep reading the
variant-map format for existing files (one-time rewrite on next save is fine).
Bonus: the 3 hand-written phase issues on ditz-metadata become parseable — the
human-obvious format becomes THE format. Do this FIRST: every other 7.x adds fields,
and they should land in the stable representation.

### 7.1 Identity without config
- [ ] Reporter = `~/.ditz-config` if present, else `$DITZ_USER`/`$DITZ_EMAIL`
      (explicit beats inferred), else `git config user.name/email`, else error
      with a real fix-it message (PR #7)
- [ ] `ditz init` no longer claims config exists when it doesn't
- [ ] `init` derives the project name from `basename(cwd)`, which in worktree
      layouts yields names like "master" — add `init --name` and default to the
      common-root basename

### 7.2 Short prefixed random IDs (`proj-a3f2k` style)
- [ ] `ditz init --prefix foo` stores prefix in project.yaml
- [ ] New issues get `foo-` + 5 random base36 chars, rerolled against the local
      tree on the (rare) collision at create time — a purely local check, no
      coordination
- [ ] Full SHA1 and `--id custom` still accepted (idempotent creates depend on
      `--id`); prefix matching already works
- Design note (2026-06-11, council review): sequential `proj-N` was REJECTED.
  (a) Nothing serializes concurrent ditz processes in one clone — two
  simultaneous `ditz add` could mint the same N and truncate-overwrite each
  other before commit. (b) Renumber-on-sync silently re-points existing
  references (commit messages, agent context, blocked_by) at a different
  issue — the worst failure mode for agents holding an ID mid-task.
  (c) The consumers are agents copying IDs out of --json; sequence carries no
  value for them, and creation order is already in creation_time.
  Random suffixes make all three hazards structurally impossible.

### 7.3 Creation-time metadata (beads: `-t` 84%, `--priority` 40%, `--parent` 19%)
- [ ] `add -t|--type bugfix|feature|task`, `-c|--component`, `-p|--priority`,
      `--parent <id>`, `--desc TEXT` (alongside existing `--desc-stdin`)

### 7.4 Priority field
- [ ] `priority: 0–4` (beads scale, default 2) in types + YAML (absent = 2)
- [ ] `set --priority`, `list --priority N`, `ready` sorts by priority then age

### 7.5 Close with reason / reopen
- [ ] `close --reason TEXT` → logged as the close event comment (54–87% of observed
      closes carry one; dispositions alone lose the why)
- [ ] `reopen <id>` (closed → unstarted, logged)

### 7.6 Generic status mutation
- [ ] `set --status unstarted|in_progress|paused` — `bd update --status` is the
      single most common mutation observed (86% of updates); agents reach for one
      verb. `start`/`stop`/`close` stay as sugar. `set` already exists; extend it.

### 7.7 Parent / epic hierarchy
- [ ] `parent: <id>` field (distinct from blocks/blocked_by)
- [ ] `add --parent`, `list --parent <id>`, `show --children`
- [ ] An "epic" is just an issue with children; no special type required

### 7.8 Dependency visibility
- [ ] `dep tree <id>` / `graph` — ASCII render over blocks/blocked_by

### 7.9 Configurable branch name
- [ ] `init --branch NAME` (un-hardcode `ditz-metadata`, git.ml)

### 7.10 Small parity items
- [ ] `count` (filters as in list), `list --limit N`
- [ ] `q`-equivalent already exists (`add -q`) — document the mapping

### 7.11 Optional fields (only if migration needs them)
- [ ] `labels: []` + `list --label`; `assignee` + `set --assignee`
      (assignee-heavy usage was Gas Town rigs, not core workflow — decide at
      migration time)

## Phase 8: Production Hardening

### 8.1 Land PR #4
Worktree/root detection fix — required for bare-repo + worktree layouts (i.e. how
tedks actually uses git). Council review (2026-06-11) found and fixed in-PR: the
bare-at-root container derivation (silent cross-project writes), the worktree
ownership check, stale-registration self-heal, init-from-bare-root crash, and
cwd-dependent empty `list` from subdirectories. Smoke test done on the real layout.

### 8.2 Write-path integrity (from the 2026-02-14 review, still valid)
- [ ] Git backend writes through the same temp-file + rename helper as FS backend
      (today: bare `open_out`, non-atomic + follows symlinks — git.ml)
- [ ] `read_yaml_file` closes channel on exception (storage.ml)
- [ ] `now_rfc3339` errors instead of silently returning epoch (issue_ops.ml)

### 8.3 Sync conflict auto-resolution
Implement the Phase 6 spec that's currently a TODO (git.ml `merge`): union
log_events, last-write-wins status by timestamp, union references;
`.ditz-conflict/` escape hatch when titles/descs diverge. With random IDs
(7.2) the only same-path conflict class is two edits of the same issue, which
this spec covers — settle the ID format before or with this work. Resolution
must always emit parseable YAML.

### 8.4 CI
GitHub Actions: nix-based `dune build` + `dune runtest` on every PR
(flake + cache action; the opam-nix toolchain must not cold-build per run).
There is currently NO CI — PR #1–4 were merged on local test claims.

### 8.5 Test isolation (rides with 8.4's CI)
Tests must never read/write the real `$HOME` or real config — the live tracker's
"Test User <test@example.com>" reporter on every issue is the scar tissue here.

### 8.6 Type-level debt (already filed as issues)
.mli interfaces, typed error variants (replace polymorphic `` `Msg ``), illegal
states unrepresentable (status × disposition). Fold into 7.x type changes where the
files are already open rather than as standalone churn.

### 8.7 Tracker cleanup (already filed: "Clean up old test issues")
Purge `issue-abc123`/`issue-abc999`; re-file or convert the 3 old-format phase
issues; close the 2 review issues already fixed on master (unseeded Random,
getenv HOME).

## Phase 9: Migration & Rollout

### 9.1 Beads import
- [ ] `ditz import beads <issues.jsonl>` (from `bd export` or `.beads/issues.jsonl`)
- [ ] Mapping: open→unstarted, in_progress→in_progress, blocked→(dep-derived),
      closed→closed+fixed; priority 1:1; parent→parent; deps→blocks/blocked_by;
      comments→log_events; beads id kept as the ditz id (idempotent re-import)

### 9.2 Distribution
- [ ] `nix build` produces the single binary; install on all machines (PATH),
      pinned via dotfiles. An agent can't adopt a tool that isn't installed.

### 9.3 Agent onboarding
- [ ] A CLAUDE.md/AGENTS.md snippet (the `bd onboard` equivalent): the ready→start→
      close loop, JSON flags, id conventions. Update any skills/docs that
      hardcode beads for migrated projects.

### 9.4 Migrate real projects
- [ ] predictionbook first (lower stakes), verify a week of daily agent use
- [ ] then goals; stop the beads daemons on both
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
