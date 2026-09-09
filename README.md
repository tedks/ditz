# ditz

A simple, light-weight distributed issue tracker designed to work with git.

Issues are plain-text YAML files, one per issue, meant to be `cat`'d, `grep`'d,
and diffed like any other text in your repo. There is no daemon, no database,
and no server: `ditz` reads and writes files, and git carries them between
clones. That makes it equally comfortable for a human at a terminal and for
an AI agent that just wants to read and write structured state as plain text.

## Quick start

```
ditz init                     # creates the ditz-metadata branch
ditz add "Fix the thing"      # add an issue
ditz ready                    # what's unblocked and unstarted?
ditz start <id>               # mark it in progress
ditz close <id> --fixed       # close it out
ditz sync                     # push/pull issue state with origin
```

## Commands

| Command | Description |
|---|---|
| `init` | Initialize a new ditz project |
| `add` | Add a new issue |
| `list` | List issues |
| `show` | Show issue details |
| `search` | Search issues by text |
| `start` / `stop` | Start or pause work on one or more issues |
| `close` / `reopen` | Close or reopen one or more issues |
| `drop` | Delete an issue |
| `set` | Update issue fields |
| `comment` | Add a comment to an issue |
| `ref` | Add a file reference to an issue |
| `blocks` / `unblocks` | Manage dependency relationships |
| `deps` | Inspect and validate the dependency graph |
| `assign` / `unassign` | Assign an issue to (or remove it from) a release |
| `status` | Project status overview |
| `ready` | Issues that are unstarted/paused and unblocked |
| `context` | Dump all open issues, optimized for LLM context |
| `import` | Import issues from a beads (`bd export`) JSONL file |
| `sync` | Sync the ditz-metadata branch with remote |
| `onboard` | Write agent-onboarding instructions into `AGENTS.md` |

Every command supports `--json` for structured output. Run `ditz COMMAND
--help` for full usage, or `ditz --help` for the complete list.

## Where issues live

Issue data lives on a dedicated orphan branch, `ditz-metadata`, so issue
churn never collides with your feature branches or pollutes your PR diffs.
`ditz sync` fetches, merges, and pushes it. See [FORMAT.md](FORMAT.md) for
the full file format and git model, including how concurrent edits merge.

## Installation

See [INSTALL.md](INSTALL.md). `ditz` is distributed as a Nix flake:

```
nix profile install github:tedks/ditz#ditz
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## History

ditz was originally created by William Morgan in 2008 as a Ruby gem. This
repository is a from-scratch OCaml rewrite by Edward Smith that keeps the
original's core idea — plain-text, git-friendly issue files — while
dropping the Ruby implementation, its plugin system, and its
RubyGems packaging in favor of a single binary and a design aimed squarely
at git-and-files workflows, including ones driven by AI agents.

## License

The original 2008 Ruby implementation was copyright William Morgan (see
[History](#history) above). This OCaml implementation shares no code with
it — it's a from-scratch rewrite of the same idea, not a derivative work —
and is copyright (C) 2026 Edward Smith.

This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version. See [LICENSE](LICENSE) for the full text.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.
