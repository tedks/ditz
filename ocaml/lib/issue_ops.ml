(** Issue lifecycle operations *)

open Types

let now_rfc3339 () =
  match Ptime.of_float_s (Unix.gettimeofday ()) with
  | Some t -> Ptime.to_rfc3339 t
  | None ->
    (* Only reachable with a system clock outside Ptime's representable range
       (year 0..9999). Silently stamping the epoch would corrupt issue
       history and last-write-wins resolution; fail loudly instead. *)
    invalid_arg "now_rfc3339: system clock out of RFC3339 range"

let add_log_event (issue : issue) ~who ~what ~comment : issue =
  let event : log_event = {
    time = now_rfc3339 ();
    who;
    what;
    comment;
  } in
  { issue with log_events = issue.log_events @ [event] }

(* [comment] carries the close reason; it lands on the close log event
   (pass "" for none). Required rather than optional to keep the subject-first
   argument order all the other ops use. *)
let close_issue (issue : issue) ~disposition ~comment ~who : issue =
  let disp_str = disposition_to_string disposition in
  let issue = { issue with status = Closed; disposition = Some disposition } in
  add_log_event issue ~who ~what:("closed: " ^ disp_str) ~comment

let start_issue (issue : issue) ~who =
  if issue.status = Closed then
    Error (`Msg (Printf.sprintf "issue %s is closed; reopen it first" issue.id))
  else
    Ok (add_log_event { issue with status = In_progress } ~who ~what:"started" ~comment:"")

let stop_issue (issue : issue) ~who =
  if issue.status = Closed then
    Error (`Msg (Printf.sprintf "issue %s is closed; reopen it first" issue.id))
  else
    Ok (add_log_event { issue with status = Paused } ~who ~what:"stopped" ~comment:"")

(* The visible inverse of close: closed -> unstarted, disposition cleared. *)
let reopen_issue (issue : issue) ~who =
  if issue.status <> Closed then
    Error (`Msg (Printf.sprintf "issue %s is not closed (nothing to reopen)" issue.id))
  else
    Ok (add_log_event { issue with status = Unstarted; disposition = None }
          ~who ~what:"reopened" ~comment:"")

(* Generic status mutation for the open states. Closing is via close_issue
   (it records a disposition), so Closed is refused here with the remedy.
   Setting an open status on a closed issue revives it (disposition cleared). *)
let set_status (issue : issue) ~status ~who =
  match status with
  | Closed ->
    Error (`Msg (Printf.sprintf
      "use 'close %s' to close an issue (it records a disposition)" issue.id))
  | _ ->
    let revived = issue.status = Closed in
    let what =
      if revived then Printf.sprintf "reopened (status -> %s)" (status_to_string status)
      else Printf.sprintf "status -> %s" (status_to_string status)
    in
    Ok (add_log_event { issue with status; disposition = None } ~who ~what ~comment:"")

let add_comment (issue : issue) ~who ~comment =
  add_log_event issue ~who ~what:"commented" ~comment

(* Dependency management *)

let add_blocks (issue : issue) ~blocked_id ~who =
  if List.mem blocked_id issue.blocks then
    issue (* Already blocking, no-op *)
  else
    let issue = { issue with blocks = issue.blocks @ [blocked_id] } in
    add_log_event issue ~who ~what:(Printf.sprintf "blocks %s" blocked_id) ~comment:""

let remove_blocks (issue : issue) ~blocked_id ~who =
  if not (List.mem blocked_id issue.blocks) then
    issue (* Not blocking, no-op *)
  else
    let issue = { issue with blocks = List.filter (fun id -> id <> blocked_id) issue.blocks } in
    add_log_event issue ~who ~what:(Printf.sprintf "no longer blocks %s" blocked_id) ~comment:""

let add_blocked_by (issue : issue) ~blocker_id ~who =
  if List.mem blocker_id issue.blocked_by then
    issue (* Already blocked, no-op *)
  else
    let issue = { issue with blocked_by = issue.blocked_by @ [blocker_id] } in
    add_log_event issue ~who ~what:(Printf.sprintf "blocked by %s" blocker_id) ~comment:""

let remove_blocked_by (issue : issue) ~blocker_id ~who =
  if not (List.mem blocker_id issue.blocked_by) then
    issue (* Not blocked, no-op *)
  else
    let issue = { issue with blocked_by = List.filter (fun id -> id <> blocker_id) issue.blocked_by } in
    add_log_event issue ~who ~what:(Printf.sprintf "no longer blocked by %s" blocker_id) ~comment:""

(* File references *)

let add_file_ref (issue : issue) ~path ~line ~note ~who =
  let ref : file_ref = { path; line; note } in
  (* Check if reference already exists *)
  let exists = List.exists (fun (r : file_ref) ->
    r.path = path && r.line = line
  ) issue.file_refs in
  if exists then
    issue (* Already exists, no-op *)
  else
    let issue = { issue with file_refs = issue.file_refs @ [ref] } in
    let loc = match line with
      | Some l -> Printf.sprintf "%s:%d" path l
      | None -> path
    in
    add_log_event issue ~who ~what:(Printf.sprintf "referenced %s" loc) ~comment:""

let remove_file_ref (issue : issue) ~path ~line ~who =
  let original_count = List.length issue.file_refs in
  let file_refs = List.filter (fun (r : file_ref) ->
    not (r.path = path && r.line = line)
  ) issue.file_refs in
  if List.length file_refs = original_count then
    issue (* Nothing removed, no-op *)
  else
    let issue = { issue with file_refs } in
    let loc = match line with
      | Some l -> Printf.sprintf "%s:%d" path l
      | None -> path
    in
    add_log_event issue ~who ~what:(Printf.sprintf "removed reference %s" loc) ~comment:""

(* Field updates *)

let set_type (issue : issue) ~issue_type ~who =
  if issue.issue_type = issue_type then
    issue
  else
    let issue = { issue with issue_type } in
    add_log_event issue ~who ~what:(Printf.sprintf "changed type to %s" (issue_type_to_string issue_type)) ~comment:""

let set_component (issue : issue) ~component ~who =
  if issue.component = component then
    issue
  else
    let old_component = issue.component in
    let issue = { issue with component } in
    add_log_event issue ~who ~what:(Printf.sprintf "changed component from %s to %s" old_component component) ~comment:""

let set_title (issue : issue) ~title ~who =
  if issue.title = title then
    issue
  else
    let issue = { issue with title } in
    add_log_event issue ~who ~what:"changed title" ~comment:""

let set_desc (issue : issue) ~desc ~who =
  let issue = { issue with desc } in
  add_log_event issue ~who ~what:"updated description" ~comment:""

let assign_release (issue : issue) ~release ~who =
  let issue = { issue with release = Some release } in
  add_log_event issue ~who ~what:(Printf.sprintf "assigned to release %s" release) ~comment:""

let unassign_release (issue : issue) ~who =
  match issue.release with
  | None -> issue
  | Some old_release ->
    let issue = { issue with release = None } in
    add_log_event issue ~who ~what:(Printf.sprintf "unassigned from release %s" old_release) ~comment:""

(* Search *)

let matches_search (issue : issue) ~query =
  let query = String.lowercase_ascii query in
  let check s = String.lowercase_ascii s |> fun s ->
    try let _ = Str.search_forward (Str.regexp_string query) s 0 in true
    with Not_found -> false
  in
  check issue.id ||
  check issue.title ||
  check issue.desc ||
  check issue.component ||
  check issue.reporter ||
  List.exists (fun (ev : log_event) -> check ev.comment) issue.log_events
