(** Tests for the beads JSONL importer (parse + map + reciprocal edges). *)

open Ditz

let last_what (i : Types.issue) =
  List.map (fun (e : Types.log_event) -> e.what) i.Types.log_events

let find_ev (i : Types.issue) what =
  List.find_opt (fun (e : Types.log_event) -> e.Types.what = what) i.Types.log_events

let () =
  (* Tolerant parse: blank lines skipped, a bad line warns (not fatal), a line
     with no id/title warns. *)
  let text =
    {|{"id":"p-1","title":"Open one","status":"open","priority":3,"issue_type":"bug","created_by":"Dev","owner":"d@e.co","created_at":"2026-01-01T00:00:00Z","labels":["x","y"]}

{"id":"p-2","title":"Closed one","status":"closed","issue_type":"task","created_at":"2026-01-02T00:00:00Z","closed_at":"2026-02-01T00:00:00Z","close_reason":"shipped","external_ref":"gh-9","dependencies":[{"issue_id":"p-2","depends_on_id":"p-1","type":"blocks"},{"issue_id":"p-2","depends_on_id":"p-1","type":"related"}]}
not json at all
{"title":"no id here"}|}
  in
  let beads, warns = Import_beads.parse_jsonl text in
  assert (List.length beads = 2);
  assert (List.length warns = 2);   (* the non-json line and the no-id line *)
  print_endline "PASS: tolerant parse (2 beads, 2 warnings, blank skipped)";

  let b1 = List.nth beads 0 and b2 = List.nth beads 1 in
  assert (b1.Import_beads.id = "p-1" && b1.Import_beads.priority = Some 3);
  assert (b1.Import_beads.labels = ["x"; "y"]);
  assert (b2.Import_beads.blockers = ["p-1"]);
  assert (b2.Import_beads.other_deps = [("related", "p-1")]);
  print_endline "PASS: field + dep parsing";

  (* Reciprocal blocks reconstruction: p-1 must end up blocking p-2 even though
     beads only recorded the edge on p-2's side. *)
  let recip = Import_beads.reciprocal_blocks beads in
  assert (Hashtbl.find recip "p-1" = ["p-2"]);
  print_endline "PASS: reciprocal blocks reconstruction";

  (* Map p-1 (open bug): unstarted, no disposition, blocks p-2, priority+labels
     in provenance, reporter from created_by+owner. *)
  let i1 = Import_beads.to_issue ~reporter_fallback:"F <f@e.co>"
      ~blocks:(Hashtbl.find recip "p-1") b1 in
  assert (i1.Types.status = Types.Unstarted);
  assert (i1.Types.disposition = None);
  assert (i1.Types.issue_type = Types.Bugfix);
  assert (i1.Types.blocks = ["p-2"]);
  assert (i1.Types.reporter = "Dev <d@e.co>");
  assert (i1.Types.creation_time = "2026-01-01T00:00:00Z");
  (match find_ev i1 "imported from beads" with
   | Some e -> assert (e.Types.comment = "priority=3; labels=x,y")
   | None -> failwith "expected provenance event");
  print_endline "PASS: map open bug (status/type/blocks/reporter/provenance)";

  (* Map p-2 (closed task): closed+fixed, close_reason on close event,
     blocked_by p-1, external_ref in references, non-blocks dep in provenance. *)
  let i2 = Import_beads.to_issue ~reporter_fallback:"F <f@e.co>" ~blocks:[] b2 in
  assert (i2.Types.status = Types.Closed);
  assert (i2.Types.disposition = Some Types.Fixed);
  assert (i2.Types.blocked_by = ["p-1"]);
  assert (i2.Types.references = ["gh-9"]);
  (match find_ev i2 "closed: fixed" with
   | Some e -> assert (e.Types.comment = "shipped"); assert (e.Types.time = "2026-02-01T00:00:00Z")
   | None -> failwith "expected close event with reason");
  (match find_ev i2 "imported from beads" with
   | Some e -> assert (e.Types.comment = "deps=related:p-1")  (* non-blocks dep preserved *)
   | None -> failwith "expected provenance with non-blocks dep");
  print_endline "PASS: map closed task (disposition/reason/blocked_by/refs/dep-provenance)";

  (* reporter fallback when bead names no owner/creator *)
  let bare = { b1 with Import_beads.created_by = None; owner = None } in
  let ib = Import_beads.to_issue ~reporter_fallback:"F <f@e.co>" ~blocks:[] bare in
  assert (ib.Types.reporter = "F <f@e.co>");
  ignore last_what;
  print_endline "PASS: reporter fallback";

  (* ---- council hardening ---- *)

  (* dedup: a duplicate id in one file is dropped (first kept) with a warning *)
  let dup_text =
    {|{"id":"d-1","title":"first","status":"open"}
{"id":"d-1","title":"second different","status":"closed"}
{"id":"d-2","title":"other","status":"open"}|}
  in
  let dbeads, _ = Import_beads.parse_jsonl dup_text in
  let deduped, dwarns = Import_beads.dedup dbeads in
  assert (List.length deduped = 2);
  assert (List.length dwarns = 1);
  assert ((List.nth deduped 0).Import_beads.title = "first");  (* first kept *)
  print_endline "PASS: dedup keeps first, warns on duplicate id";

  (* sanitize_edges: an endpoint that will not exist after the import is
     dropped + warned. "known" spans both the records being imported and what
     the tracker already holds, so a syntactically fine but unknown id such as
     "ghost-1" is dropped too -- keeping it would leave `deps --check` calling
     the graph DANGLING. *)
  let known id = List.mem id ["good-1"] in
  let bad_edge = { b1 with Import_beads.blockers = ["good-1"; "bad.id"; "ghost-1"] } in
  let sed, swarns = Import_beads.sanitize_edges ~known [bad_edge] in
  assert ((List.hd sed).Import_beads.blockers = ["good-1"]);
  assert (List.length swarns = 2);
  print_endline "PASS: sanitize_edges drops unknown endpoints (invalid AND dangling), warns";

  (* malformed `dependencies` (not an array) warns rather than vanishing *)
  let mal_text = {|{"id":"m-1","title":"t","dependencies":"oops"}|} in
  let _, mwarns = Import_beads.parse_jsonl mal_text in
  assert (List.exists (fun w ->
    let contains hay nee = let hl=String.length hay and nl=String.length nee in
      let rec go i = i+nl<=hl && (String.sub hay i nl = nee || go (i+1)) in go 0 in
    contains w "not an array") mwarns);
  print_endline "PASS: malformed dependencies warns";

  (* updated_at + assignee survive as provenance (the "nothing lost" promise) *)
  let prov_text =
    {|{"id":"pr-1","title":"t","status":"open","updated_at":"2026-03-03T00:00:00Z","assignee":"alice"}|}
  in
  let pbeads, _ = Import_beads.parse_jsonl prov_text in
  let pi = Import_beads.to_issue ~reporter_fallback:"F <f@e.co>" ~blocks:[] (List.hd pbeads) in
  (match find_ev pi "imported from beads" with
   | Some e ->
     let has s = let hl=String.length e.Types.comment and nl=String.length s in
       let rec go i = i+nl<=hl && (String.sub e.Types.comment i nl = s || go (i+1)) in go 0 in
     assert (has "assignee=alice"); assert (has "updated_at=2026-03-03T00:00:00Z")
   | None -> failwith "expected provenance with assignee + updated_at");
  print_endline "PASS: updated_at + assignee preserved as provenance";

  (* escaped newline in a description stays one physical line / one issue *)
  let nl_text = {|{"id":"n-1","title":"t","description":"line1\nline2\nline3","status":"open"}|} in
  let nbeads, nwarns = Import_beads.parse_jsonl nl_text in
  assert (List.length nbeads = 1 && nwarns = []);
  assert ((List.hd nbeads).Import_beads.desc = "line1\nline2\nline3");
  print_endline "PASS: escaped newline in description";

  (* --- id sanitization: rename instead of drop, edges follow --- *)
  let dotted =
    {|{"id":"g-53u","title":"epic","status":"open"}
{"id":"g-53u.1","title":"child","status":"open","dependencies":[{"issue_id":"g-53u.1","depends_on_id":"g-53u","type":"parent-child"}]}
{"id":"g-9","title":"blocked by child","status":"open","dependencies":[{"issue_id":"g-9","depends_on_id":"g-53u.1","type":"blocks"}]}|}
  in
  let dbeads, dwarns = Import_beads.parse_jsonl dotted in
  assert (dwarns = []);
  let dbeads, notices, rwarns = Import_beads.sanitize_ids dbeads in
  assert (rwarns = []);                          (* a rename loses nothing *)
  assert (List.length notices = 1);
  let ids = List.map (fun (b : Import_beads.bead) -> b.Import_beads.id) dbeads in
  assert (ids = [ "g-53u"; "g-53u-1"; "g-9" ]);
  (* the endpoint of an edge naming the renamed issue is rewritten too *)
  let child = List.nth dbeads 1 and blocked = List.nth dbeads 2 in
  assert (child.Import_beads.parents = [ "g-53u" ]);
  assert (child.Import_beads.orig_id = Some "g-53u.1");
  assert (blocked.Import_beads.blockers = [ "g-53u-1" ]);
  print_endline "PASS: sanitize_ids renames dotted ids and rewrites edge endpoints";

  (* A rename onto an id another record owns is loss, not a rename: the issue
     is refused and warned rather than silently merged. Both input orders. *)
  let collide_a = {|{"id":"a-b","title":"incumbent","status":"open"}
{"id":"a.b","title":"would be swallowed","status":"open"}|} in
  let cb, _ = Import_beads.parse_jsonl collide_a in
  let kept, cnotices, cwarns = Import_beads.sanitize_ids cb in
  assert (List.length cwarns = 1 && cnotices = []);
  assert (List.map (fun (b : Import_beads.bead) -> b.Import_beads.title) kept = [ "incumbent" ]);
  let collide_b = {|{"id":"a.b","title":"renamed first","status":"open"}
{"id":"a-b","title":"native second","status":"open"}|} in
  let cb2, _ = Import_beads.parse_jsonl collide_b in
  let kept2, _, cwarns2 = Import_beads.sanitize_ids cb2 in
  (* the native owner is claimed up front, so the rename is the one refused *)
  assert (List.length cwarns2 = 1);
  assert (List.map (fun (b : Import_beads.bead) -> b.Import_beads.title) kept2 = [ "native second" ]);
  (* two invalid ids sanitizing to the same target: first wins, second refused *)
  let collide_c = {|{"id":"a.b","title":"first dotted","status":"open"}
{"id":"a-b","title":"native","status":"open"}
{"id":"a:b","title":"second punct","status":"open"}|} in
  let cb3, _ = Import_beads.parse_jsonl collide_c in
  let kept3, _, cwarns3 = Import_beads.sanitize_ids cb3 in
  assert (List.length cwarns3 = 2 && List.length kept3 = 1);
  print_endline "PASS: rename collision refuses the issue and warns (both orders, multi-way)";

  (* A destination collision is judged by [taken]: an unrelated occupant is
     refused, but re-importing the SAME issue is a benign rename. *)
  let one = {|{"id":"a.b","title":"mine","status":"open"}|} in
  let ob, _ = Import_beads.parse_jsonl one in
  let _, _, tw = Import_beads.sanitize_ids ~taken:(fun _ -> true) ob in
  assert (List.length tw = 1);
  let okept, onotices, ow = Import_beads.sanitize_ids ~taken:(fun _ -> false) ob in
  assert (ow = [] && List.length onotices = 1 && List.length okept = 1);
  print_endline "PASS: destination collision refused; same-issue re-import stays a rename";

  (* Identity proof: beads_id= provenance is matched whole-segment, so
     beads_id=g-1 does not match a record whose provenance says beads_id=g-10. *)
  let mk_prov c =
    { (Import_beads.to_issue ~reporter_fallback:"F <f@e.co>" ~blocks:[] (List.hd ob)) with
      Types.log_events = [ { Types.time = "t"; who = "w"; what = "imported from beads"; comment = c } ] }
  in
  assert (Import_beads.issue_has_beads_id (mk_prov "priority=2; beads_id=g-1") "g-1");
  assert (not (Import_beads.issue_has_beads_id (mk_prov "beads_id=g-10") "g-1"));
  assert (not (Import_beads.issue_has_beads_id (mk_prov "priority=2") "g-1"));
  print_endline "PASS: beads_id identity match is whole-segment, not substring";

  (* An id renaming cannot rescue is still dropped, and that is loss. *)
  let empty_id = {|{"id":"","title":"no id","status":"open"}|} in
  let eb, _ = Import_beads.parse_jsonl empty_id in
  let ekept, _, _ = Import_beads.sanitize_ids eb in
  assert (List.length ekept = 1 && (List.hd ekept).Import_beads.id = "");
  print_endline "PASS: an unrescuable id survives sanitize_ids for the caller to drop";

  (* A present-but-wrong-typed field is data we were handed and discarded, so
     it warns; an absent field stays silent. Regression guard for the
     evaluation-order bug that read the warning ref before the accessors ran. *)
  let bad_types =
    {|{"id":"bt-1","title":"t","status":"open","acceptance_criteria":42,"labels":["ok",7],"priority":"nope"}
{"id":"bt-2","title":"t","status":"open"}|}
  in
  let btb, btw = Import_beads.parse_jsonl bad_types in
  assert (List.length btb = 2);
  let has_sub hay nee =
    let hl = String.length hay and nl = String.length nee in
    let rec go i = i + nl <= hl && (String.sub hay i nl = nee || go (i + 1)) in go 0
  in
  assert (List.exists (fun w -> has_sub w "acceptance_criteria") btw);
  assert (List.exists (fun w -> has_sub w "labels") btw);
  assert (List.exists (fun w -> has_sub w "priority") btw);
  assert (not (List.exists (fun w -> has_sub w "bt-2") btw));
  assert ((List.nth btb 0).Import_beads.labels = [ "ok" ]);
  print_endline "PASS: wrong-typed fields warn (and absent ones do not)";

  (* A beads status ditz has no counterpart for maps to Unstarted but is kept. *)
  let odd_status = {|{"id":"os-1","title":"t","status":"deferred"}|} in
  let osb, _ = Import_beads.parse_jsonl odd_status in
  let osi = Import_beads.to_issue ~reporter_fallback:"F <f@e.co>" ~blocks:[] (List.hd osb) in
  assert (osi.Types.status = Types.Unstarted);
  (match find_ev osi "imported from beads" with
   | Some e -> assert (has_sub e.Types.comment "beads_status=deferred")
   | None -> failwith "expected beads_status provenance");
  (* a recognized status, whatever its case, adds no noise *)
  let ok_status = {|{"id":"os-2","title":"t","status":"Open"}|} in
  let osb2, _ = Import_beads.parse_jsonl ok_status in
  let osi2 = Import_beads.to_issue ~reporter_fallback:"F <f@e.co>" ~blocks:[] (List.hd osb2) in
  assert (osi2.Types.status = Types.Unstarted);
  (match find_ev osi2 "imported from beads" with
   | Some e -> assert (not (has_sub e.Types.comment "beads_status"))
   | None -> ());
  print_endline "PASS: unrecognized status kept in provenance; recognized (any case) adds none";

  (* a plain duplicate id is dedup's business, not sanitize_ids' — no double report *)
  let dup2 = {|{"id":"x-1","title":"one","status":"open"}
{"id":"x-1","title":"two","status":"open"}|} in
  let d2, _ = Import_beads.parse_jsonl dup2 in
  let _, _, d2warns = Import_beads.sanitize_ids d2 in
  assert (d2warns = []);
  print_endline "PASS: plain duplicate id is not double-reported as a collision";

  (* --- parent-child becomes a real edge in both directions --- *)
  let kids = Import_beads.children_by_parent dbeads in
  assert (Hashtbl.find kids "g-53u" = [ "g-53u-1" ]);
  let recip2 = Import_beads.reciprocal_blocks dbeads in
  let child_issue =
    Import_beads.to_issue ~reporter_fallback:"F <f@e.co>"
      ~blocks:(try Hashtbl.find recip2 "g-53u-1" with Not_found -> [])
      ~blocked_by_extra:[] child
  in
  (* child blocks its parent... *)
  assert (List.mem "g-53u" child_issue.Types.blocks);
  (* ...and still records that g-9 depends on it *)
  assert (List.mem "g-9" child_issue.Types.blocks);
  let parent_issue =
    Import_beads.to_issue ~reporter_fallback:"F <f@e.co>" ~blocks:[]
      ~blocked_by_extra:(Hashtbl.find kids "g-53u") (List.hd dbeads)
  in
  assert (parent_issue.Types.blocked_by = [ "g-53u-1" ]);
  print_endline "PASS: parent-child maps to child-blocks-parent, both directions";

  (* the renamed issue keeps its original beads id in provenance *)
  (match find_ev child_issue "imported from beads" with
   | Some e ->
     let has s = let hl=String.length e.Types.comment and nl=String.length s in
       let rec go i = i+nl<=hl && (String.sub e.Types.comment i nl = s || go (i+1)) in go 0 in
     assert (has "beads_id=g-53u.1")
   | None -> failwith "expected provenance with original beads id");
  print_endline "PASS: pre-rename beads id preserved in provenance";

  (* --- acceptance_criteria is folded into desc, never dropped --- *)
  let acc_text =
    {|{"id":"ac-1","title":"t","status":"open","description":"body here","acceptance_criteria":"must not crash"}
{"id":"ac-2","title":"t","status":"open","acceptance_criteria":"only criteria"}
{"id":"ac-3","title":"t","status":"open","description":"body only"}|}
  in
  let abeads, _ = Import_beads.parse_jsonl acc_text in
  let mk b = Import_beads.to_issue ~reporter_fallback:"F <f@e.co>" ~blocks:[] b in
  let a1 = mk (List.nth abeads 0) and a2 = mk (List.nth abeads 1) and a3 = mk (List.nth abeads 2) in
  assert (a1.Types.desc = "body here\n\nAcceptance: must not crash");
  assert (a2.Types.desc = "Acceptance: only criteria");  (* no empty leading blank *)
  assert (a3.Types.desc = "body only");                  (* absent field changes nothing *)
  print_endline "PASS: acceptance_criteria folded into desc";

  (* --- beads types ditz has no counterpart for stay recoverable --- *)
  let ty_text =
    {|{"id":"ty-1","title":"t","status":"open","issue_type":"epic"}
{"id":"ty-2","title":"t","status":"open","issue_type":"chore"}
{"id":"ty-3","title":"t","status":"open","issue_type":"bug"}
{"id":"ty-4","title":"t","status":"open","issue_type":"task"}|}
  in
  let tbeads, _ = Import_beads.parse_jsonl ty_text in
  let mkt b = Import_beads.to_issue ~reporter_fallback:"F <f@e.co>" ~blocks:[] b in
  let prov_of i =
    match find_ev i "imported from beads" with Some e -> e.Types.comment | None -> ""
  in
  let has hay nee =
    let hl = String.length hay and nl = String.length nee in
    let rec go i = i + nl <= hl && (String.sub hay i nl = nee || go (i + 1)) in go 0
  in
  let t1 = mkt (List.nth tbeads 0) and t2 = mkt (List.nth tbeads 1) in
  let t3 = mkt (List.nth tbeads 2) and t4 = mkt (List.nth tbeads 3) in
  assert (t1.Types.issue_type = Types.Task && has (prov_of t1) "beads_type=epic");
  assert (t2.Types.issue_type = Types.Task && has (prov_of t2) "beads_type=chore");
  (* a recognized alias renames without losing anything, so it adds no noise *)
  assert (t3.Types.issue_type = Types.Bugfix && not (has (prov_of t3) "beads_type"));
  assert (t4.Types.issue_type = Types.Task && not (has (prov_of t4) "beads_type"));
  print_endline "PASS: unmapped beads types recorded in provenance";

  print_endline "\nAll import_beads tests passed!"
