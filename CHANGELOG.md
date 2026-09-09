# Changelog

All notable changes to ditz will be documented in this file. This changelog
starts fresh with the OCaml rewrite; see git history for the 2008-2011 Ruby
project's changes.

## Unreleased

Initial OCaml implementation. Not yet tagged; still pre-1.0.

### Added
- Core issue lifecycle: `init`, `add`, `list`, `show`, `search`, `start`,
  `stop`, `close`, `reopen`, `drop`, `set`, `comment`
- File references (`ref`) and dependency tracking (`blocks`/`unblocks`,
  `deps` for graph inspection, cycle detection, and validation)
- Release management (`assign`/`unassign`), project overview (`status`)
- `--json` on every command, plus `context` and `ready` for agent workflows
- `import` for migrating issues from a beads (`bd export`) JSONL file
- Git-backed storage: issue data lives on an orphan `ditz-metadata` branch,
  accessed through a persistent sparse worktree; `sync` fetches/merges/pushes
  it, with automatic conflict resolution for non-overlapping edits
- `onboard` to write agent-onboarding instructions into `AGENTS.md`
- Distribution via a Nix flake (`nix profile install github:tedks/ditz#ditz`)
