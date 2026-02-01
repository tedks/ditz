(** Tests for issue lifecycle transitions and log events. *)

open Ditz

let base_issue id =
  {
    Types.id;
    title = "Test issue";
    desc = "";
    issue_type = Types.Task;
    component = "default";
    release = None;
    reporter = "Tester <test@example.com>";
    status = Types.Unstarted;
    disposition = None;
    creation_time = "2026-01-30T00:00:00Z";
    references = [];
    log_events = [{
      Types.time = "2026-01-30T00:00:00Z";
      who = "Tester";
      what = "created";
      comment = "";
    }];
    blocks = [];
    blocked_by = [];
    file_refs = [];
  }

let last_log_event (issue : Types.issue) =
  match List.rev issue.Types.log_events with
  | ev :: _ -> ev
  | [] -> failwith "expected at least one log event"

let expect_error = function
  | Ok _ -> failwith "expected error"
  | Error _ -> ()

let () =
  let issue = base_issue "abc123" in

  let closed = Issue_ops.close_issue issue ~who:"Tester" ~disposition:Types.Fixed in
  assert (closed.Types.status = Types.Closed);
  assert (closed.Types.disposition = Some Types.Fixed);
  let closed_ev = last_log_event closed in
  assert (closed_ev.Types.what = "closed: fixed");
  assert (closed_ev.Types.who = "Tester");
  assert (closed_ev.Types.comment = "");

  expect_error (Issue_ops.start_issue closed ~who:"Tester");
  expect_error (Issue_ops.stop_issue closed ~who:"Tester");

  let started =
    match Issue_ops.start_issue issue ~who:"Tester" with
    | Ok v -> v
    | Error (`Msg e) -> failwith e
  in
  assert (started.Types.status = Types.In_progress);
  assert (List.length started.Types.log_events = 2);
  assert ((last_log_event started).Types.what = "started");

  let stopped =
    match Issue_ops.stop_issue started ~who:"Tester" with
    | Ok v -> v
    | Error (`Msg e) -> failwith e
  in
  assert (stopped.Types.status = Types.Paused);
  assert (List.length stopped.Types.log_events = 3);
  assert ((last_log_event stopped).Types.what = "stopped")
