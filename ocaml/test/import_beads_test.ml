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

  print_endline "\nAll import_beads tests passed!"
