(** Tests for set field operations. *)

open Ditz

let base_issue id =
  {
    Types.id;
    title = "Original title";
    desc = "Original description";
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

let () =
  let issue = base_issue "abc123" in

  (* Test set_type *)
  let issue = Issue_ops.set_type issue ~issue_type:Types.Bugfix ~who:"Tester" in
  assert (issue.Types.issue_type = Types.Bugfix);
  assert (String.sub (last_log_event issue).Types.what 0 12 = "changed type");

  (* Setting same type is no-op *)
  let issue_before = issue in
  let issue = Issue_ops.set_type issue ~issue_type:Types.Bugfix ~who:"Tester" in
  assert (List.length issue.Types.log_events = List.length issue_before.Types.log_events);

  (* Test set_component *)
  let issue = Issue_ops.set_component issue ~component:"auth" ~who:"Tester" in
  assert (issue.Types.component = "auth");
  assert (String.sub (last_log_event issue).Types.what 0 17 = "changed component");

  (* Test set_title *)
  let issue = Issue_ops.set_title issue ~title:"New title" ~who:"Tester" in
  assert (issue.Types.title = "New title");
  assert ((last_log_event issue).Types.what = "changed title");

  (* Test set_desc *)
  let issue = Issue_ops.set_desc issue ~desc:"New description" ~who:"Tester" in
  assert (issue.Types.desc = "New description");
  assert ((last_log_event issue).Types.what = "updated description");

  (* Test assign_release *)
  let issue = Issue_ops.assign_release issue ~release:"v1.0" ~who:"Tester" in
  assert (issue.Types.release = Some "v1.0");
  assert (String.sub (last_log_event issue).Types.what 0 8 = "assigned");

  (* Test unassign_release *)
  let issue = Issue_ops.unassign_release issue ~who:"Tester" in
  assert (issue.Types.release = None);
  assert (String.sub (last_log_event issue).Types.what 0 10 = "unassigned");

  (* Unassigning when not assigned is no-op *)
  let issue_before = issue in
  let issue = Issue_ops.unassign_release issue ~who:"Tester" in
  assert (List.length issue.Types.log_events = List.length issue_before.Types.log_events);

  (* 7.3: new_issue constructs a fresh unstarted issue with a created event *)
  let fresh = Issue_ops.new_issue ~id:"new1" ~title:"Fresh" ~desc:"a desc"
    ~issue_type:Types.Bugfix ~component:"auth"
    ~reporter:"R <r@example.com>" ~who:"R" in
  assert (fresh.Types.id = "new1");
  assert (fresh.Types.title = "Fresh");
  assert (fresh.Types.desc = "a desc");
  assert (fresh.Types.issue_type = Types.Bugfix);
  assert (fresh.Types.component = "auth");
  assert (fresh.Types.reporter = "R <r@example.com>");
  assert (fresh.Types.status = Types.Unstarted);
  assert (fresh.Types.disposition = None);
  assert (fresh.Types.release = None);
  assert (fresh.Types.blocks = [] && fresh.Types.blocked_by = [] && fresh.Types.file_refs = []);
  (match fresh.Types.log_events with
   | [ev] -> assert (ev.Types.what = "created"); assert (ev.Types.who = "R")
   | _ -> failwith "expected exactly one created event");

  print_endline "Set fields tests passed"
