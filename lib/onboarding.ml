(** The agent-onboarding snippet `ditz init` writes into a repo's AGENTS.md,
    and a clobber-safe installer for it. Agent-first delivery: it lands in the
    file agents already read on arrival and travels with the project via git,
    instead of being a doc they must discover. *)

let marker_start = "<!-- ditz:onboard -->"
let marker_end = "<!-- /ditz:onboard -->"
let historical_snippets = Onboarding_history.snippets

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
- `ditz show <id>` · `ditz list --status open|unstarted|in_progress|paused|closed` (comma-separate to combine) · `ditz search <q>`
- `--json` on any command for machine output; `--ids-only` for just ids

Naming issues: there is no separate name field — `--id` IS the name.
- `ditz add "title" --id <name>` makes `<name>` the permanent id (ASCII
  letters, digits, `-`, `_`); without `--id` you get a SHA1. Other commands
  that take an id accept any unique prefix (an exact id always wins);
  `add --id` itself matches exactly.
- Re-running `add --id <name>` for an existing issue changes NOTHING (safe to
  retry, but not an update). Edit with e.g. `ditz set <id> --title "..."`
  (also `--desc`, `-t`, `-c`).

Structure (there are no priority / epic / parent fields — urgency is derived,
hierarchy is expressed in the graph):
- grouping: `-c <component>` + `ditz list --component <c>`
- sequencing: `ditz blocks <a> <b>` (a blocks b); an "epic" is just an issue
  blocked by its members — it stays out of `ready` until they close
- `ditz deps <id>` shows the dependency tree; `ditz deps --check` validates it

Sync: `ditz sync` fetches/merges/pushes the metadata branch. See the
[format reference](https://github.com/tedks/ditz/blob/master/FORMAT.md) for the
file format and git model, and the
[agent recipes](https://github.com/tedks/ditz/blob/master/docs/agent-recipes.md)
for creation, retry, and recovery examples.
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

(* Return every occurrence, so duplicate or reversed markers cannot authorize a
   refresh. Exact sentinels embedded in prose also count as ambiguous. *)
let marker_positions text marker =
  let last = String.length text - String.length marker in
  let rec scan i acc =
    if i > last then List.rev acc
    else if String.sub text i (String.length marker) = marker then
      scan (i + String.length marker) (i :: acc)
    else scan (i + 1) acc
  in
  scan 0 []

let block snippet = Printf.sprintf "%s\n%s\n%s" marker_start snippet marker_end

(** Default installation appends a marked block, skipping any existing start
    marker. Explicit refresh replaces only one intact, byte-exact generated
    block. Unknown or malformed blocks are refused, including orphan end markers.
    Bytes outside the markers are preserved, including their trailing newline.

    Symlinks are followed only when their resolved target is inside [within].
    Without a repo context, external/dangling links and non-regular files are
    refused. This retains the existing atomic-write and path-resolution model;
    it does not synchronize concurrent editors. *)
let install_with_refresh ~refresh ~within ~path : outcome =
  let write_block dest existing =
    let write content =
      match Fs_util.write_file_atomic ~path:dest ~content with
      | Ok () -> Wrote dest
      | Error (`Msg e) -> Failed e
    in
    let append () =
      let generated = block snippet ^ "\n" in
      write (if existing = "" then generated else existing ^ "\n" ^ generated)
    in
    if not refresh then
      (* Keep default behavior, including its skip on a lone start marker. *)
      if contains existing marker_start then Skipped_present dest else append ()
    else
      match marker_positions existing marker_start, marker_positions existing marker_end with
      | [], [] -> append ()
      | [first], [last] when first < last ->
        let after = last + String.length marker_end in
        let at_line_start = first = 0 || existing.[first - 1] = '\n' in
        let at_line_end = after = String.length existing || existing.[after] = '\n' in
        let present = String.sub existing first (after - first) in
        if not at_line_start || not at_line_end then
          Failed (dest ^ " has inline onboarding markers; left unchanged")
        else if present = block snippet then Skipped_present dest
        else if List.exists (fun old -> present = block old) historical_snippets then
          write (String.sub existing 0 first ^ block snippet ^
                 String.sub existing after (String.length existing - after))
        else Failed (dest ^ " has an edited or unknown onboarding block; left unchanged")
      | _ -> Failed (dest ^ " has incomplete, reversed, or duplicate onboarding markers; left unchanged")
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

let install ~within ~path = install_with_refresh ~refresh:false ~within ~path
let refresh ~within ~path = install_with_refresh ~refresh:true ~within ~path
