# Updating agent instructions

`ditz init` installs a marked ditz block in the working-tree root's `AGENTS.md`.
`ditz onboard` installs the same block without initializing a tracker. Outside
a Git repository it uses `AGENTS.md` in the current directory. Existing text is
preserved; if a start marker already exists, ordinary onboarding skips it.

After upgrading ditz, explicitly refresh an unchanged generated block:

```sh
ditz onboard --refresh
```

Refresh recognizes one complete pair of sentinel lines,
`<!-- ditz:onboard -->` and `<!-- /ditz:onboard -->`. It replaces the block only
when its contents exactly match a known generated version. All bytes before the
start marker and after the end marker remain unchanged. A current block is a
no-op. A file without either marker receives the normal appended block.

Edited or unknown blocks, partial/reversed/duplicate markers, inline markers,
and line-ending conversions are refused without writing. This includes a file
that quotes the sentinel strings elsewhere. Review those files manually; do not
remove a project's instructions just to make refresh pass. Ordinary `onboard`
retains its old skip behavior even for an incomplete start marker.

The recognized historical snippets are stored literally in
[`lib/onboarding_history.ml`](../lib/onboarding_history.ml), with their source
commit beside each entry. They cover the six distinct snippets introduced by
`ea1e1d3`, `d0eaaf7`, `cdd5d69`, `3867001`, `2439961`, and `fd0ac13`, including
versions used before their PRs merged. Matching is byte-for-byte, not a checksum
or a similarity heuristic. Historical entries must remain immutable when the
current snippet changes.

`AGENTS.md` may point to another regular file inside the repository, such as
`CLAUDE.md`. Onboarding updates that resolved target and preserves the symlink.
External and dangling symlinks are refused, as are all symlinks without a
repository context. Refresh preserves an existing regular file's permission
bits, setting them on the temporary file before atomic replacement; new files
retain ordinary onboarding's `0600` creation mode. It does not coordinate with
concurrent text editors or protect against concurrent path replacement.

`--json` keeps the existing `{ "path": "...", "onboarding": "..." }` shape:
`wrote` for installation or replacement, `already-present` for a current block,
`failed` for a rejected block or an I/O failure, and `refused-symlink` for an
unsafe link. `failed` exits 1; the other outcomes retain exit 0. Inspect the
outcome as well as the exit code. Human output explains a rejected block;
JSON does not include the diagnostic. `--ids-only` prints a successful target
path and is silent on failures and refused symlinks.
