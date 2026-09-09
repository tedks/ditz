(** Tests for file reference management. *)

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

let () =
  let issue = base_issue "abc123" in

  (* Test add_file_ref with line number *)
  let issue = Issue_ops.add_file_ref issue ~path:"src/auth.ml" ~line:(Some 42) ~note:(Some "bug here") ~who:"Tester" in
  assert (List.length issue.Types.file_refs = 1);
  let ref = List.hd issue.Types.file_refs in
  assert (ref.Types.path = "src/auth.ml");
  assert (ref.Types.line = Some 42);
  assert (ref.Types.note = Some "bug here");
  assert (String.sub (last_log_event issue).Types.what 0 10 = "referenced");

  (* Test add_file_ref without line number *)
  let issue = Issue_ops.add_file_ref issue ~path:"README.md" ~line:None ~note:None ~who:"Tester" in
  assert (List.length issue.Types.file_refs = 2);

  (* Test idempotence - adding same ref again is no-op *)
  let issue_before = issue in
  let issue = Issue_ops.add_file_ref issue ~path:"src/auth.ml" ~line:(Some 42) ~note:(Some "different note") ~who:"Tester" in
  assert (List.length issue.Types.file_refs = List.length issue_before.Types.file_refs);
  assert (List.length issue.Types.log_events = List.length issue_before.Types.log_events);

  (* Test remove_file_ref *)
  let issue = Issue_ops.remove_file_ref issue ~path:"src/auth.ml" ~line:(Some 42) ~who:"Tester" in
  assert (List.length issue.Types.file_refs = 1);
  assert (String.sub (last_log_event issue).Types.what 0 7 = "removed");

  (* Test removing non-existent is no-op *)
  let issue_before = issue in
  let issue = Issue_ops.remove_file_ref issue ~path:"nonexistent.ml" ~line:None ~who:"Tester" in
  assert (List.length issue.Types.log_events = List.length issue_before.Types.log_events);

  print_endline "File reference tests passed"
