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

  let closed = Issue_ops.close_issue issue ~who:"Tester" ~disposition:Types.Fixed ~comment:"" in
  assert (closed.Types.status = Types.Closed);
  assert (closed.Types.disposition = Some Types.Fixed);
  let closed_ev = last_log_event closed in
  assert (closed_ev.Types.what = "closed: fixed");
  assert (closed_ev.Types.who = "Tester");
  assert (closed_ev.Types.comment = "");

  (* 7.2: close --reason lands on the close event's comment *)
  let closed_reason =
    Issue_ops.close_issue issue ~who:"Tester" ~disposition:Types.Wontfix
      ~comment:"superseded by xyz"
  in
  let cr_ev = last_log_event closed_reason in
  assert (cr_ev.Types.what = "closed: wontfix");
  assert (cr_ev.Types.comment = "superseded by xyz");

  expect_error (Issue_ops.start_issue closed ~who:"Tester");
  expect_error (Issue_ops.stop_issue closed ~who:"Tester");

  (* 7.2: reopen revives a closed issue, clears disposition, logs *)
  let reopened =
    match Issue_ops.reopen_issue closed ~who:"Tester" with
    | Ok v -> v | Error (`Msg e) -> failwith e
  in
  assert (reopened.Types.status = Types.Unstarted);
  assert (reopened.Types.disposition = None);
  assert ((last_log_event reopened).Types.what = "reopened");
  (* reopen only applies to closed issues *)
  expect_error (Issue_ops.reopen_issue reopened ~who:"Tester");
  (* after reopen, start works again *)
  (match Issue_ops.start_issue reopened ~who:"Tester" with
   | Ok v -> assert (v.Types.status = Types.In_progress)
   | Error (`Msg e) -> failwith e);

  (* 7.2: set_status handles the open states; refuses Closed (use close);
     revives a closed issue when set to an open state *)
  let paused =
    match Issue_ops.set_status issue ~status:Types.Paused ~who:"Tester" with
    | Ok v -> v | Error (`Msg e) -> failwith e
  in
  assert (paused.Types.status = Types.Paused);
  assert ((last_log_event paused).Types.what = "status -> paused");
  expect_error (Issue_ops.set_status issue ~status:Types.Closed ~who:"Tester");
  let revived =
    match Issue_ops.set_status closed ~status:Types.In_progress ~who:"Tester" with
    | Ok v -> v | Error (`Msg e) -> failwith e
  in
  assert (revived.Types.status = Types.In_progress);
  assert (revived.Types.disposition = None);
  assert ((last_log_event revived).Types.what = "reopened (status -> in_progress)");

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
