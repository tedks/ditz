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

  (* sanitize_edges: a blocking edge to an invalid (dotted) id is dropped + warned *)
  let valid id = String.for_all (function
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' | '_' -> true | _ -> false) id && id <> "" in
  let bad_edge = { b1 with Import_beads.blockers = ["good-1"; "bad.id"] } in
  let sed, swarns = Import_beads.sanitize_edges ~valid [bad_edge] in
  assert ((List.hd sed).Import_beads.blockers = ["good-1"]);
  assert (List.length swarns = 1);
  print_endline "PASS: sanitize_edges drops invalid endpoint, warns";

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

  print_endline "\nAll import_beads tests passed!"
