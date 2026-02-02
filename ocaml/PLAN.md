# ditz OCaml Rewrite Plan

## Philosophy

Keep it simple. The original ditz was ~2200 lines of Ruby. We should be able to match functionality in ~1000 lines of OCaml. No sqlite, no daemons, no sync complexity. Just YAML files in a directory that you commit with git.

The killer feature for the AI era: agents can read and write issues as plain text files.

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

## Non-Goals

Things we're explicitly NOT doing:
- No sqlite (files only)
- No daemon process
- No complex merge driver (auto-resolve or bail)
- No external service integration (no JIRA bridge)
- No web UI server

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

1. **Issue ID format**: Keep SHA1 hashes or switch to shorter IDs?
   - Leaning: Support both. Generate short IDs by default (8 chars), accept full SHA1.
   - Allow `--id custom-name` for deterministic/human IDs.

2. **Config location**: `~/.ditz-config` or `~/.config/ditz/config.yaml`?
   - Leaning: `~/.config/ditz/config.yaml` (XDG compliant)
   - But support legacy `~/.ditz-config` for backward compat.

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
