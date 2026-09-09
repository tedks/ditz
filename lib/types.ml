(** Core domain types for ditz *)

(* Enum YAML converters are hand-written (below) rather than derived. The ppx
   emits a variant-map form (`type:\n  Task: []`) that breaks the founding
   "cat-able, greppable" mission. We emit plain scalars (`type: task`) and read
   BOTH the scalar form and the legacy variant-map form, so existing files keep
   loading and rewrite to scalars on their next save. *)
type issue_type = Bugfix | Feature | Task
type issue_status = Unstarted | In_progress | Paused | Closed
type disposition = Fixed | Wontfix | Reorg
type release_status = Unreleased | Released

(* Scalar names — single source of truth for both display and YAML. *)
let issue_type_to_string = function
  | Bugfix -> "bugfix"
  | Feature -> "feature"
  | Task -> "task"

let status_to_string = function
  | Unstarted -> "unstarted"
  | In_progress -> "in_progress"
  | Paused -> "paused"
  | Closed -> "closed"

let disposition_to_string = function
  | Fixed -> "fixed"
  | Wontfix -> "wontfix"
  | Reorg -> "reorg"

let release_status_to_string = function
  | Unreleased -> "unreleased"
  | Released -> "released"

(* Read an enum written either as a scalar ("task") or the legacy ppx
   variant-map ({Task: []}); normalize to a lowercased tag. *)
let yaml_enum_tag = function
  | `String s -> Some (String.lowercase_ascii (String.trim s))
  | `O [(name, _)] -> Some (String.lowercase_ascii (String.trim name))
  | _ -> None

let enum_of_yaml ~what parse yaml =
  match yaml_enum_tag yaml with
  | Some tag ->
    (match parse tag with
     | Some v -> Ok v
     | None -> Error (`Msg (Printf.sprintf "invalid %s: %s" what tag)))
  | None -> Error (`Msg (Printf.sprintf "invalid %s: expected scalar" what))

let issue_type_to_yaml t : Yaml.value = `String (issue_type_to_string t)
let issue_type_of_yaml yaml =
  enum_of_yaml ~what:"type"
    (function
      | "bugfix" -> Some Bugfix
      | "feature" -> Some Feature
      | "task" -> Some Task
      | _ -> None)
    yaml

let issue_status_to_yaml s : Yaml.value = `String (status_to_string s)
let issue_status_of_yaml yaml =
  enum_of_yaml ~what:"status"
    (function
      | "unstarted" -> Some Unstarted
      | "in_progress" -> Some In_progress
      | "paused" -> Some Paused
      | "closed" -> Some Closed
      | _ -> None)
    yaml

let disposition_to_yaml d : Yaml.value = `String (disposition_to_string d)
let disposition_of_yaml yaml =
  enum_of_yaml ~what:"disposition"
    (function
      | "fixed" -> Some Fixed
      | "wontfix" -> Some Wontfix
      | "reorg" -> Some Reorg
      | _ -> None)
    yaml

let release_status_to_yaml r : Yaml.value = `String (release_status_to_string r)
let release_status_of_yaml yaml =
  enum_of_yaml ~what:"release_status"
    (function
      | "unreleased" -> Some Unreleased
      | "released" -> Some Released
      | _ -> None)
    yaml

(* Records derive their YAML; the enum field converters above are resolved by
   name (foo_to_yaml / foo_of_yaml), so the records emit clean scalars too. *)
type log_event = {
  time: string; (* ISO8601 *)
  who: string;
  what: string;
  comment: string;
}
[@@deriving yaml]

type file_ref = {
  path: string;
  line: int option;
  note: string option;
}
[@@deriving yaml]

type issue = {
  id: string;
  title: string;
  desc: string;
  issue_type: issue_type; [@key "type"]
  component: string;
  release: string option;
  reporter: string;
  status: issue_status;
  disposition: disposition option;
  creation_time: string;
  references: string list;
  log_events: log_event list;
  blocks: string list; [@default []]
  blocked_by: string list; [@default []]
  file_refs: file_ref list; [@default []]
}
[@@deriving yaml]

type component = {
  name: string;
}
[@@deriving yaml]

type release = {
  name: string;
  status: release_status;
  release_time: string option;
  log_events: log_event list;
}
[@@deriving yaml]

type project = {
  name: string;
  version: string;
  components: component list;
  releases: release list;
}
[@@deriving yaml]

type config = {
  name: string;
  email: string;
  issue_dir: string;
}
[@@deriving yaml]

(* Helpers *)

let () = Random.self_init ()

let make_id ~title ~desc ~reporter =
  let now = Ptime_clock.now () |> Ptime.to_rfc3339 in
  let data = String.concat "\n" [now; string_of_float (Random.float 1.0); reporter; title; desc] in
  Digestif.SHA1.(digest_string data |> to_hex)

let status_widget = function
  | Unstarted -> "_"
  | In_progress -> ">"
  | Paused -> "="
  | Closed -> "x"

(* JSON output helpers *)

let escape_json_string s =
  let b = Buffer.create (String.length s * 2) in
  String.iter (fun c ->
    match c with
    | '"' -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n"
    | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | c when Char.code c < 32 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char b c
  ) s;
  Buffer.contents b

let file_ref_to_json (ref : file_ref) =
  let line_str = match ref.line with
    | Some l -> Printf.sprintf "%d" l
    | None -> "null"
  in
  let note_str = match ref.note with
    | Some n -> Printf.sprintf {|"%s"|} (escape_json_string n)
    | None -> "null"
  in
  Printf.sprintf {|{"path":"%s","line":%s,"note":%s}|}
    (escape_json_string ref.path) line_str note_str

let log_event_to_json (ev : log_event) =
  Printf.sprintf {|{"time":"%s","who":"%s","what":"%s","comment":"%s"}|}
    (escape_json_string ev.time)
    (escape_json_string ev.who)
    (escape_json_string ev.what)
    (escape_json_string ev.comment)

let option_to_json f = function
  | None -> "null"
  | Some x -> f x

let list_to_json f xs =
  "[" ^ (String.concat "," (List.map f xs)) ^ "]"

let string_to_json s = Printf.sprintf {|"%s"|} (escape_json_string s)

let issue_to_json issue =
  Printf.sprintf
    {|{"id":"%s","title":"%s","desc":"%s","type":"%s","component":"%s","release":%s,"reporter":"%s","status":"%s","disposition":%s,"creation_time":"%s","references":%s,"log_events":%s,"blocks":%s,"blocked_by":%s,"file_refs":%s}|}
    (escape_json_string issue.id)
    (escape_json_string issue.title)
    (escape_json_string issue.desc)
    (issue_type_to_string issue.issue_type)
    (escape_json_string issue.component)
    (option_to_json string_to_json issue.release)
    (escape_json_string issue.reporter)
    (status_to_string issue.status)
    (option_to_json (fun d -> string_to_json (disposition_to_string d)) issue.disposition)
    (escape_json_string issue.creation_time)
    (list_to_json string_to_json issue.references)
    (list_to_json log_event_to_json issue.log_events)
    (list_to_json string_to_json issue.blocks)
    (list_to_json string_to_json issue.blocked_by)
    (list_to_json file_ref_to_json issue.file_refs)

let issues_to_json issues =
  list_to_json issue_to_json issues

let simple_issue_json issue =
  Printf.sprintf {|{"id":"%s","title":"%s","status":"%s"}|}
    (escape_json_string issue.id)
    (escape_json_string issue.title)
    (status_to_string issue.status)
