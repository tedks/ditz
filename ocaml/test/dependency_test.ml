(** Tests for dependency management (blocks/blocked_by). *)

open Ditz

let base_issue id =
  {
    Types.id;
    title = "Test issue " ^ id;
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
  let blocker = base_issue "blocker1" in
  let blocked = base_issue "blocked1" in

  (* Test add_blocks *)
  let blocker = Issue_ops.add_blocks blocker ~blocked_id:"blocked1" ~who:"Tester" in
  assert (List.mem "blocked1" blocker.Types.blocks);
  assert (String.sub (last_log_event blocker).Types.what 0 6 = "blocks");

  (* Test add_blocked_by *)
  let blocked = Issue_ops.add_blocked_by blocked ~blocker_id:"blocker1" ~who:"Tester" in
  assert (List.mem "blocker1" blocked.Types.blocked_by);
  assert (String.sub (last_log_event blocked).Types.what 0 7 = "blocked");

  (* Test idempotence - adding again should be no-op *)
  let blocker_before = blocker in
  let blocker = Issue_ops.add_blocks blocker ~blocked_id:"blocked1" ~who:"Tester" in
  assert (List.length blocker.Types.blocks = List.length blocker_before.Types.blocks);
  assert (List.length blocker.Types.log_events = List.length blocker_before.Types.log_events);

  (* Test remove_blocks *)
  let blocker = Issue_ops.remove_blocks blocker ~blocked_id:"blocked1" ~who:"Tester" in
  assert (not (List.mem "blocked1" blocker.Types.blocks));
  assert (String.sub (last_log_event blocker).Types.what 0 10 = "no longer ");

  (* Test remove_blocked_by *)
  let blocked = Issue_ops.remove_blocked_by blocked ~blocker_id:"blocker1" ~who:"Tester" in
  assert (not (List.mem "blocker1" blocked.Types.blocked_by));

  (* Test removing non-existent is no-op *)
  let blocked_before = blocked in
  let blocked = Issue_ops.remove_blocked_by blocked ~blocker_id:"nonexistent" ~who:"Tester" in
  assert (List.length blocked.Types.log_events = List.length blocked_before.Types.log_events);

  print_endline "Dependency tests passed"
