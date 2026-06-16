(** The agent-onboarding snippet `ditz init` writes into a repo's AGENTS.md,
    and a clobber-safe installer for it. Agent-first delivery: it lands in the
    file agents already read on arrival and travels with the project via git,
    instead of being a doc they must discover. *)

let marker_start = "<!-- ditz:onboard -->"
let marker_end = "<!-- /ditz:onboard -->"

(* Kept terse on purpose — this is loaded into an agent's context. FORMAT.md is
   the fuller reference. *)
let snippet = {ditz|## Issue tracking with ditz

This project uses `ditz` (not beads). Issues are plain-text YAML on the
`ditz-metadata` git branch; the `ditz` CLI reads and writes them.

The loop:
- `ditz ready` — what to work on now (unblocked, ranked by how much each unblocks)
- `ditz start <id>` — mark in progress
- `ditz close <id> --reason "..."` — close with why (or `--wontfix` / `--reorg`)
- `ditz reopen <id>` — revive a closed issue

Create / inspect:
- `ditz add "title" -t bugfix|feature|task -c <component> --desc "..."`
- `ditz show <id>` · `ditz list --status unstarted|in_progress|paused|closed` · `ditz search <q>`
- `--json` on any command for machine output; `--ids-only` for just ids
- ids: copy them from output; a unique prefix works (like git hashes);
  `--id <name>` sets a deterministic id (re-creating with it is idempotent)

Structure (there are no priority / epic / parent fields — urgency is derived,
hierarchy is expressed in the graph):
- grouping: `-c <component>` + `ditz list --component <c>`
- sequencing: `ditz blocks <a> <b>` (a blocks b); an "epic" is just an issue
  blocked by its members — it stays out of `ready` until they close
- `ditz deps <id>` shows the dependency tree; `ditz deps --check` validates it

Sync: `ditz sync` fetches/merges/pushes the metadata branch. See FORMAT.md for
the file format and git model.
|ditz}

(* Wrote/Skipped carry the file actually touched — which may be a symlink's
   resolved target (e.g. CLAUDE.md), not the path passed in (AGENTS.md) — so
   callers report what really changed. *)
type outcome =
  | Wrote of string
  | Skipped_present of string
  | Refused_symlink
  | Failed of string

let contains hay nee =
  let hl = String.length hay and nl = String.length nee in
  if nl = 0 then true
  else
    let rec go i = i + nl <= hl && (String.sub hay i nl = nee || go (i + 1)) in
    go 0

(* Is [target] (an absolute real path) inside directory [root]? *)
let within_dir ~root target =
  match (try Some (Unix.realpath root) with _ -> None) with
  | None -> false
  | Some rr ->
    let rr = if rr <> "" && rr.[String.length rr - 1] = '/' then rr else rr ^ "/" in
    String.starts_with ~prefix:rr target

(** Install the snippet into [path] (e.g. "AGENTS.md"), appended between sentinel
    markers. Non-destructive: never overwrites existing content; a no-op if the
    markers are already present.

    Symlink handling: these files are commonly symlinked to a canonical
    instruction file, and writing through one could corrupt it. So we follow a
    symlink ONLY when it resolves to a real file inside [within] (the repo) —
    e.g. AGENTS.md -> ./CLAUDE.md — and write to that target; a symlink that
    resolves outside the repo (e.g. ~/.claude/CLAUDE.md), or a chain leaving it,
    is refused. With [within] = None there's no repo context, so any symlink is
    refused. *)
let install ~within ~path : outcome =
  let write_block dest existing =
    (* Skip on the start marker alone: never append a second block (no
       duplicates), and don't auto-"repair" a hand-mangled block. *)
    if contains existing marker_start then Skipped_present dest
    else
      let block = Printf.sprintf "%s\n%s\n%s\n" marker_start snippet marker_end in
      let content = if existing = "" then block else existing ^ "\n" ^ block in
      (match Fs_util.write_file_atomic ~path:dest ~content with
       | Ok () -> Wrote dest
       | Error (`Msg e) -> Failed e)
  in
  (* Append into a concrete (already de-symlinked) destination. *)
  let install_concrete dest =
    match (try Some (Unix.lstat dest) with Unix.Unix_error _ -> None) with
    | None -> write_block dest ""   (* nothing there: create fresh *)
    | Some st ->
      (match st.Unix.st_kind with
       | Unix.S_REG ->
         (* CRITICAL: an existing-but-unreadable file must NOT be treated as
            empty — that would atomically replace (destroy) it. Refuse instead. *)
         (match (try Some (Fs_util.read_file dest) with _ -> None) with
          | Some existing -> write_block dest existing
          | None -> Failed (dest ^ " exists but could not be read; left unchanged"))
       | Unix.S_LNK -> Refused_symlink   (* defensive; caller resolved already *)
       | _ -> Failed (dest ^ " is not a regular file; left unchanged"))
  in
  match (try Some (Unix.lstat path) with Unix.Unix_error _ -> None) with
  | Some st when st.Unix.st_kind = Unix.S_LNK ->
    (match within with
     | Some root ->
       (match (try Some (Unix.realpath path) with _ -> None) with
        | Some real when within_dir ~root real -> install_concrete real
        | _ -> Refused_symlink)
     | None -> Refused_symlink)
  | _ -> install_concrete path
