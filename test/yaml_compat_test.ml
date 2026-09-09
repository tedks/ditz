(** Tests for YAML compatibility and defaults. *)

open Ditz

let parse_issue s =
  match Yaml.of_string s with
  | Error (`Msg e) -> failwith e
  | Ok yaml ->
    match Types.issue_of_yaml yaml with
    | Ok issue -> issue
    | Error (`Msg e) -> failwith e

let legacy_yaml_missing_fields = {|
id: abc123
title: Legacy issue
desc: ""
type:
  Task: []
component: default
release:
reporter: Tester <test@example.com>
status:
  Unstarted: []
disposition:
creation_time: 2026-01-30T00:00:00Z
references: []
log_events: []
|}

let yaml_with_partial_file_refs = {|
id: abc124
title: File ref issue
desc: ""
type:
  Task: []
component: default
release:
reporter: Tester <test@example.com>
status:
  Unstarted: []
disposition:
creation_time: 2026-01-30T00:00:00Z
references: []
log_events: []
blocks: []
blocked_by: []
file_refs:
- path: src/main.ml
|}

let () =
  let issue = parse_issue legacy_yaml_missing_fields in
  assert (issue.Types.blocks = []);
  assert (issue.Types.blocked_by = []);
  assert (issue.Types.file_refs = []);

  let round_trip =
    issue
    |> Types.issue_to_yaml
    |> Yaml.to_string_exn
    |> parse_issue
  in
  assert (round_trip.Types.blocks = []);
  assert (round_trip.Types.blocked_by = []);
  assert (round_trip.Types.file_refs = []);

  let issue = parse_issue yaml_with_partial_file_refs in
  (match issue.Types.file_refs with
   | [{ Types.path; line = None; note = None }] ->
     assert (path = "src/main.ml")
   | _ -> failwith "expected file_refs with missing line/note to parse");

  (* 7.0: enums emit as plain scalars (cat-able/greppable), not variant maps *)
  let emitted =
    { Types.id = "scalar1"; title = "Scalar"; desc = "d"; issue_type = Types.Bugfix;
      component = "default"; release = None; reporter = "R <r@e.co>";
      status = Types.In_progress; disposition = Some Types.Fixed;
      creation_time = "2026-06-14T00:00:00Z"; references = []; log_events = [];
      blocks = []; blocked_by = []; file_refs = [] }
    |> Types.issue_to_yaml |> Yaml.to_string_exn
  in
  let contains needle =
    let hl = String.length emitted and nl = String.length needle in
    let rec go i = i + nl <= hl && (String.sub emitted i nl = needle || go (i + 1)) in
    go 0
  in
  assert (contains "type: bugfix");
  assert (contains "status: in_progress");
  assert (contains "disposition: fixed");
  assert (not (contains "Bugfix"));   (* no variant-map leakage *)
  assert (not (contains "In_progress"));

  (* 7.0: the legacy variant-map form still parses (existing files keep loading) *)
  let legacy_variant_maps = {|
id: legacy-enums
title: Legacy enums
desc: ""
type:
  Feature: []
component: default
release:
reporter: Tester <test@example.com>
status:
  Paused: []
disposition:
  Wontfix: []
creation_time: 2026-01-30T00:00:00Z
references: []
log_events: []
|} in
  let li = parse_issue legacy_variant_maps in
  assert (li.Types.issue_type = Types.Feature);
  assert (li.Types.status = Types.Paused);
  assert (li.Types.disposition = Some Types.Wontfix);

  (* and a legacy issue rewrites to scalar form on round trip *)
  let rewritten = li |> Types.issue_to_yaml |> Yaml.to_string_exn in
  let contains2 needle =
    let hl = String.length rewritten and nl = String.length needle in
    let rec go i = i + nl <= hl && (String.sub rewritten i nl = needle || go (i + 1)) in
    go 0
  in
  assert (contains2 "type: feature");
  assert (contains2 "status: paused");
  assert (not (contains2 "Feature"));
  print_endline "yaml_compat tests passed"
