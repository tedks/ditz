(** Three-way semantic merge of issues, used by `ditz sync` to auto-resolve
    git conflicts on the metadata branch. Pure: no git, no I/O.

    Strategy (PLAN.md Phase 6 / 8.3):
    - log_events: append-only by design -> union, dedup, sorted by time
    - status+disposition: treated as one unit; if the sides differ, the side
      whose latest log event is newer wins (last-write-wins); ties keep ours
    - reference-ish lists (references, blocks, blocked_by, file_refs):
      three-way set merge when a base is available (additions kept, deletions
      honored, no resurrection); plain union otherwise
    - identity-ish scalars (title, desc, type, component, release, reporter,
      creation_time): three-way pick; changed on BOTH sides -> conflict, we
      never guess
    All times are RFC3339 strings; comparison parses via Ptime and falls back
    to string order for unparseable values (better than dropping data). *)

open Types

let time_order (a : string) (b : string) =
  match Ptime.of_rfc3339 a, Ptime.of_rfc3339 b with
  | Ok (ta, _, _), Ok (tb, _, _) -> Ptime.compare ta tb
  | _ -> String.compare a b

(** The newest event time on an issue, falling back to creation_time. *)
let latest_activity (i : issue) =
  List.fold_left
    (fun acc (e : log_event) -> if time_order e.time acc > 0 then e.time else acc)
    i.creation_time i.log_events

let dedup_keep_order xs =
  List.fold_left (fun acc x -> if List.mem x acc then acc else x :: acc) [] xs
  |> List.rev

let union_events (ours : log_event list) (theirs : log_event list) =
  dedup_keep_order (ours @ theirs)
  |> List.stable_sort (fun (a : log_event) (b : log_event) -> time_order a.time b.time)

(** Three-way set merge: keep base survivors that neither side deleted, plus
    both sides' additions. Without a base, fall back to union. *)
let merge_list ~base ~ours ~theirs =
  match base with
  | None -> dedup_keep_order (ours @ theirs)
  | Some base ->
    let survivors =
      List.filter (fun x -> List.mem x ours && List.mem x theirs) base
    in
    let additions side = List.filter (fun x -> not (List.mem x base)) side in
    dedup_keep_order (survivors @ additions ours @ additions theirs)

type 'a pick = Picked of 'a | Both_changed

let pick3 ~base ~ours ~theirs =
  if ours = theirs then Picked ours
  else
    match base with
    | Some b when ours = b -> Picked theirs
    | Some b when theirs = b -> Picked ours
    | _ -> Both_changed

(** Merge two divergent versions of the same issue.
    [base] is the common ancestor when git can provide one. *)
let merge_issues ~(base : issue option) ~(ours : issue) ~(theirs : issue) :
  (issue, string) result =
  let field name ~get =
    match
      pick3
        ~base:(Option.map get base)
        ~ours:(get ours) ~theirs:(get theirs)
    with
    | Picked v -> Ok v
    | Both_changed -> Error name
  in
  let ( let* ) = Result.bind in
  let* id = field "id" ~get:(fun i -> i.id) in
  let* title = field "title" ~get:(fun i -> i.title) in
  let* desc = field "desc" ~get:(fun i -> i.desc) in
  let* issue_type = field "type" ~get:(fun i -> i.issue_type) in
  let* component = field "component" ~get:(fun i -> i.component) in
  let* release = field "release" ~get:(fun i -> i.release) in
  let* reporter = field "reporter" ~get:(fun i -> i.reporter) in
  let* creation_time = field "creation_time" ~get:(fun i -> i.creation_time) in
  let status, disposition =
    if ours.status = theirs.status && ours.disposition = theirs.disposition then
      (ours.status, ours.disposition)
    else if time_order (latest_activity theirs) (latest_activity ours) > 0 then
      (theirs.status, theirs.disposition)
    else (ours.status, ours.disposition)
  in
  let pick_list get =
    merge_list ~base:(Option.map get base) ~ours:(get ours) ~theirs:(get theirs)
  in
  Ok
    {
      id;
      title;
      desc;
      issue_type;
      component;
      release;
      reporter;
      status;
      disposition;
      creation_time;
      references = pick_list (fun i -> i.references);
      log_events = union_events ours.log_events theirs.log_events;
      blocks = pick_list (fun i -> i.blocks);
      blocked_by = pick_list (fun i -> i.blocked_by);
      file_refs = pick_list (fun i -> i.file_refs);
    }

(* Serialization helpers so callers (git.ml) need no Storage dependency. *)

let issue_of_string s =
  match Yaml.of_string s with
  | Error (`Msg e) -> Error (`Msg ("YAML parse error: " ^ e))
  | Ok y -> issue_of_yaml y

let issue_to_string i = Yaml.to_string_exn (issue_to_yaml i)
