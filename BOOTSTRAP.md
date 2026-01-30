# Ditz Bootstrap Plan

## Goal

Get ditz to the point where we can track the remaining ditz work in ditz itself.

**Bootstrap threshold:** `ditz init`, `ditz add`, `ditz list`, `ditz show`, `ditz close`, `ditz sync` all working.

## Agent Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Main Claude (you, future reader)                               │
│  - Orchestrates agents                                          │
│  - Reviews and merges PRs                                       │
│  - Tracks progress via ditz-metadata branch                     │
└─────────────────────────────────────────────────────────────────┘
        │
        ├─── Claude: Epic 1 (Core Commands)
        │    └─── Codex: Implement show/start/stop/close
        │
        ├─── Claude: Epic 2 (Git Integration)
        │    └─── Codex: Implement sync command
        │
        └─── Claude: Epic 3 (AI Experience)
             └─── Codex: Implement --json, context, ready

Each Claude agent gets its own worktree branched from master.
Stacked PRs: Epic1 → Epic2 → Epic3 (Epic2 depends on Epic1, etc.)
```

## Worktree Setup

```bash
cd ~/Projects/ditz

# Create worktrees for each epic
git worktree add ../ditz-epic1 -b epic1-core-commands master
git worktree add ../ditz-epic2 -b epic2-git-integration master
git worktree add ../ditz-epic3 -b epic3-ai-experience master
```

## Epic 1: Core Commands (Bootstrap Critical)

**Branch:** `epic1-core-commands`
**Worktree:** `~/Projects/ditz-epic1`
**Blocked by:** Nothing
**Goal:** Basic issue lifecycle working

### Tasks

1. **Fix types.ml** - Add blocks/blocked_by fields, file references
2. **Implement show <id>** - Display full issue details
3. **Implement close <id>** - Close with disposition
4. **Implement start/stop <id>** - Status transitions
5. **Implement drop <id>** - Delete issue file
6. **Test with original Ruby ditz issues** - Backward compat

### Spawn Command

```bash
/spawn-agent chaos:epic1 claude ~/Projects/ditz-epic1 "You are implementing Epic 1: Core Commands for the ditz OCaml rewrite. Read ocaml/PLAN.md for context. Your goal is to implement show, close, start, stop, drop commands. Use /ask-agent codex for implementation grunt work. When done, create a PR targeting master. The bootstrap goal is: get ditz working enough to track ditz work in ditz."
```

## Epic 2: Git Integration (Bootstrap Critical)

**Branch:** `epic2-git-integration`
**Worktree:** `~/Projects/ditz-epic2`
**Blocked by:** Epic 1 (needs working storage layer)
**Goal:** `ditz sync` working with ditz-metadata branch

### Tasks

1. **Implement ditz-metadata branch detection** - Find/create orphan branch
2. **Implement temp worktree checkout** - Read/write to branch without disturbing working tree
3. **Implement sync command** - Fetch, merge, push
4. **Implement auto-commit on write** - Every add/close/etc commits to branch
5. **Conflict detection** - Detect when manual resolution needed

### Spawn Command

```bash
/spawn-agent chaos:epic2 claude ~/Projects/ditz-epic2 "You are implementing Epic 2: Git Integration for the ditz OCaml rewrite. Read ocaml/PLAN.md Phase 6 for context. Your goal is to implement the ditz-metadata branch workflow and sync command. Merge epic1-core-commands into your branch first when it's ready. Use /ask-agent codex for implementation. When done, create a PR targeting epic1-core-commands (stacked PR)."
```

## Epic 3: AI Experience

**Branch:** `epic3-ai-experience`
**Worktree:** `~/Projects/ditz-epic3`
**Blocked by:** Epic 1
**Goal:** Make ditz great for AI agents

### Tasks

1. **Add --json flag** - JSON output for all commands
2. **Add -q flag** - Quiet mode (just IDs)
3. **Implement context command** - Dump everything for LLM context
4. **Implement ready command** - Show actionable issues
5. **Implement batch operations** - Multiple IDs to close/start

### Spawn Command

```bash
/spawn-agent chaos:epic3 claude ~/Projects/ditz-epic3 "You are implementing Epic 3: AI Experience for the ditz OCaml rewrite. Read ocaml/PLAN.md Phase 5 for context. Your goal is to add --json, -q, context, ready commands. Merge epic1-core-commands into your branch first when it's ready. Use /ask-agent codex for implementation. When done, create a PR targeting epic1-core-commands (stacked PR)."
```

## Merge Strategy (Stacked PRs)

Use /stacked-prs skill for merging:

1. Epic 1 PR merges to master first
2. Epic 2 rebases onto master, PR updated to target master
3. Epic 3 rebases onto master, PR updated to target master

Or parallel merge if no conflicts:
1. Epic 1 → master
2. Epic 2 → master (after Epic 1 merged)
3. Epic 3 → master (after Epic 1 merged, can be parallel with Epic 2)

## Bootstrap Milestone

When these commands work:

```bash
cd ~/Projects/ditz
ditz init                           # Creates ditz-metadata branch
ditz add "Implement edit command"   # Commits to ditz-metadata
ditz list                           # Shows issues
ditz show <id>                      # Full details
ditz close <id> --fixed             # Closes issue
ditz sync                           # Pushes to origin
```

Then we delete the manual issues in ditz-metadata and start using ditz to track ditz.

## For the Orchestrating Claude

When you resume this work:

1. Create the worktrees (commands above)
2. Spawn the Epic 1 agent first (it's not blocked)
3. Wait for Epic 1 to have basic storage working
4. Spawn Epic 2 and Epic 3 (they can run in parallel once Epic 1 has types.ml solid)
5. Use /stacked-prs to merge in order
6. When bootstrap milestone reached, celebrate

## Notes

- Each agent should read PLAN.md first
- Agents can use /ask-agent codex for implementation
- Agents should commit frequently
- Agents should create draft PRs early
- The orchestrator (you) merges PRs

Let's build this thing.
