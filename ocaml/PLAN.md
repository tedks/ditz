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

## Phase 1: Core Commands

### Issue Lifecycle
- [ ] `show <id>` - Display full issue details
- [ ] `start <id>` - Mark issue in_progress
- [ ] `stop <id>` - Mark issue paused
- [ ] `close <id> [--fixed|--wontfix|--reorg]` - Close with disposition
- [ ] `drop <id>` - Delete an issue

### Issue Modification
- [ ] `edit <id>` - Open issue in $EDITOR
- [ ] `comment <id>` - Add comment to log
- [ ] `assign <id> <release>` - Assign to release
- [ ] `unassign <id>` - Remove from release
- [ ] `set-component <id> <component>` - Change component

### Project Management
- [ ] `status` - Overview of project state
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

## Non-Goals

Things we're explicitly NOT doing:
- No sqlite (files only)
- No daemon process
- No sync/merge driver (just use git)
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

1. **Issue ID format**: Keep SHA1 hashes or switch to shorter IDs (nanoid)?
2. **Config location**: `~/.ditz-config` or `~/.config/ditz/config.yaml`?
3. **Backward compat**: How much effort to spend on reading Ruby ditz repos?
4. **Name**: Keep "ditz" or rename? (ditz-ng, oditz, etc.)
