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
  match issue.Types.file_refs with
  | [{ Types.path; line = None; note = None }] ->
    assert (path = "src/main.ml")
  | _ -> failwith "expected file_refs with missing line/note to parse"
