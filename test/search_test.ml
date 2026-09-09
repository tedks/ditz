(** Tests for search functionality. *)

open Ditz

let make_issue ~id ~title ~desc ~component =
  {
    Types.id;
    title;
    desc;
    issue_type = Types.Task;
    component;
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

let () =
  (* Create test issues *)
  let issue1 = make_issue ~id:"auth001" ~title:"Fix authentication bug" ~desc:"Login fails on Firefox" ~component:"auth" in
  let issue2 = make_issue ~id:"ui002" ~title:"Update button styles" ~desc:"Make buttons more visible" ~component:"frontend" in
  let issue3 = make_issue ~id:"api003" ~title:"Add API endpoint" ~desc:"Need authentication check" ~component:"backend" in

  (* Search by title *)
  assert (Issue_ops.matches_search issue1 ~query:"authentication");
  assert (not (Issue_ops.matches_search issue2 ~query:"authentication"));
  assert (Issue_ops.matches_search issue3 ~query:"authentication");

  (* Search by description *)
  assert (Issue_ops.matches_search issue1 ~query:"Firefox");
  assert (not (Issue_ops.matches_search issue2 ~query:"Firefox"));

  (* Search by component *)
  assert (Issue_ops.matches_search issue1 ~query:"auth");
  assert (Issue_ops.matches_search issue2 ~query:"frontend");

  (* Search by ID *)
  assert (Issue_ops.matches_search issue1 ~query:"auth001");
  assert (not (Issue_ops.matches_search issue2 ~query:"auth001"));

  (* Case insensitive *)
  assert (Issue_ops.matches_search issue1 ~query:"AUTHENTICATION");
  assert (Issue_ops.matches_search issue1 ~query:"firefox");
  assert (Issue_ops.matches_search issue2 ~query:"BUTTON");

  (* Partial match *)
  assert (Issue_ops.matches_search issue1 ~query:"auth");
  assert (Issue_ops.matches_search issue2 ~query:"button");

  (* Test with comment in log_events *)
  let issue_with_comment = Issue_ops.add_comment issue1 ~who:"Tester" ~comment:"This is related to cookies" in
  assert (Issue_ops.matches_search issue_with_comment ~query:"cookies");
  assert (not (Issue_ops.matches_search issue1 ~query:"cookies"));

  print_endline "Search tests passed"
