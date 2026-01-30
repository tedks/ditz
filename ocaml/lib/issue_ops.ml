(** Issue lifecycle operations *)

open Types

let now_rfc3339 () =
  match Ptime.of_float_s (Unix.gettimeofday ()) with
  | Some t -> Ptime.to_rfc3339 t
  | None -> "1970-01-01T00:00:00Z"

let add_log_event (issue : issue) ~who ~what ~comment : issue =
  let event : log_event = {
    time = now_rfc3339 ();
    who;
    what;
    comment;
  } in
  { issue with log_events = issue.log_events @ [event] }

let close_issue (issue : issue) ~who ~disposition : issue =
  let disp_str = disposition_to_string disposition in
  let issue = { issue with status = Closed; disposition = Some disposition } in
  add_log_event issue ~who ~what:("closed: " ^ disp_str) ~comment:""

let start_issue (issue : issue) ~who =
  if issue.status = Closed then
    Error (`Msg (Printf.sprintf "issue %s is closed" issue.id))
  else
    Ok (add_log_event { issue with status = In_progress } ~who ~what:"started" ~comment:"")

let stop_issue (issue : issue) ~who =
  if issue.status = Closed then
    Error (`Msg (Printf.sprintf "issue %s is closed" issue.id))
  else
    Ok (add_log_event { issue with status = Paused } ~who ~what:"stopped" ~comment:"")
