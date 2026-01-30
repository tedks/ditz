(** Core domain types for ditz *)

type issue_type = Bugfix | Feature | Task
[@@deriving yaml]

type issue_status = Unstarted | In_progress | Paused | Closed
[@@deriving yaml]

type disposition = Fixed | Wontfix | Reorg
[@@deriving yaml]

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
  blocks: string list;
  blocked_by: string list;
  file_refs: file_ref list;
}
[@@deriving yaml]

type component = {
  name: string;
}
[@@deriving yaml]

type release_status = Unreleased | Released
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

let make_id ~title ~desc ~reporter =
  let now = Ptime_clock.now () |> Ptime.to_rfc3339 in
  let data = String.concat "\n" [now; string_of_float (Random.float 1.0); reporter; title; desc] in
  Digestif.SHA1.(digest_string data |> to_hex)

let issue_type_to_string = function
  | Bugfix -> "bugfix"
  | Feature -> "feature"
  | Task -> "task"

let status_to_string = function
  | Unstarted -> "unstarted"
  | In_progress -> "in_progress"
  | Paused -> "paused"
  | Closed -> "closed"

let status_widget = function
  | Unstarted -> "_"
  | In_progress -> ">"
  | Paused -> "="
  | Closed -> "x"

let disposition_to_string = function
  | Fixed -> "fixed"
  | Wontfix -> "wontfix"
  | Reorg -> "reorg"
