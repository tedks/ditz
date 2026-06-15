(** Tolerant importer for `bd export` JSONL (beads -> ditz).

    The beads schema is the unstable EXTERNAL half, so it is isolated here:
    every field is optional, unknown fields are ignored, and a malformed line
    becomes a warning rather than aborting the import. The ditz-side mapping
    (status/disposition, the no-priority-field decision, epics-as-blocks) lives
    in [to_issue]. JSON is parsed via the yaml library (JSON ⊂ YAML), so no
    extra dependency. *)

open Types

(* One issue as it appears in a beads export line. Strings only; we don't model
   beads' full schema, just what maps to ditz. *)
type bead = {
  id : string;
  title : string;
  desc : string;
  status : string;
  priority : int option;
  itype : string;
  owner : string option;
  assignee : string option;
  created_by : string option;
  created_at : string option;
  updated_at : string option;
  closed_at : string option;
  close_reason : string option;
  external_ref : string option;
  labels : string list;
  notes : string option;
  (* ids that block THIS issue (depends_on_id of each type="blocks" dep) *)
  blockers : string list;
  (* non-"blocks" deps as (type, depends_on_id): preserved as provenance, not
     turned into graph edges — their direction (esp. parent-child) isn't safe
     to guess without real data. Revisit when migrating a tracker that uses
     them (goals); predictionbook is flat. *)
  other_deps : (string * string) list;
}

(* ---- tolerant accessors over a parsed JSON object ---- *)

let fields = function `O kvs -> kvs | _ -> []

let str_field kvs k =
  match List.assoc_opt k kvs with Some (`String s) -> Some s | _ -> None

let int_field kvs k =
  match List.assoc_opt k kvs with
  | Some (`Float f) -> Some (int_of_float f)
  | Some (`String s) -> int_of_string_opt s
  | _ -> None

let str_list_field kvs k =
  match List.assoc_opt k kvs with
  | Some (`A items) -> List.filter_map (function `String s -> Some s | _ -> None) items
  | _ -> []

(* beads deps live on the blocked issue: {depends_on_id, type:"blocks"}.
   We keep only type="blocks" edges as graph blockers; other types
   (related/parent-child/discovered-from) are surfaced as provenance, not
   silently turned into blocking edges with a guessed direction. Returns
   (blockers, other_deps, warnings) — a present-but-malformed `dependencies`
   field warns rather than vanishing, since a dropped edge is real data loss. *)
let parse_deps kvs =
  match List.assoc_opt "dependencies" kvs with
  | None | Some `Null -> ([], [], [])
  | Some (`A items) ->
    List.fold_left
      (fun (blk, other, warns) item ->
        let f = fields item in
        match str_field f "type", str_field f "depends_on_id" with
        | Some "blocks", Some dep -> (dep :: blk, other, warns)
        | Some t, Some dep -> (blk, (t, dep) :: other, warns)
        | _ -> (blk, other, "dependency entry missing type/depends_on_id" :: warns))
      ([], [], []) items
    |> fun (blk, other, w) -> (List.rev blk, List.rev other, List.rev w)
  | Some _ -> ([], [], [ "`dependencies` is not an array; dependencies ignored" ])

(* Returns the bead plus any field-level warnings (e.g. malformed deps). *)
let bead_of_yaml (y : Yaml.value) : (bead * string list, string) result =
  let kvs = fields y in
  match str_field kvs "id", str_field kvs "title" with
  | None, _ -> Error "line has no string id"
  | _, None -> Error "line has no string title"
  | Some id, Some title ->
    let blockers, other_deps, dep_warns = parse_deps kvs in
    Ok ({
      id; title;
      desc = Option.value (str_field kvs "description") ~default:"";
      status = Option.value (str_field kvs "status") ~default:"open";
      priority = int_field kvs "priority";
      itype = Option.value (str_field kvs "issue_type") ~default:"task";
      owner = str_field kvs "owner";
      assignee = str_field kvs "assignee";
      created_by = str_field kvs "created_by";
      created_at = str_field kvs "created_at";
      updated_at = str_field kvs "updated_at";
      closed_at = str_field kvs "closed_at";
      close_reason = str_field kvs "close_reason";
      external_ref = str_field kvs "external_ref";
      labels = str_list_field kvs "labels";
      notes = str_field kvs "notes";
      blockers;
      other_deps;
    }, List.map (Printf.sprintf "%s: %s" id) dep_warns)

(** Parse JSONL. Returns (beads, warnings); a bad line is a warning, not fatal. *)
let parse_jsonl (text : string) : bead list * string list =
  let lines = String.split_on_char '\n' text in
  List.fold_left
    (fun (beads, warns) (lineno, line) ->
      if String.trim line = "" then (beads, warns)
      else
        match Yaml.of_string line with
        | Error (`Msg e) -> (beads, Printf.sprintf "line %d: YAML/JSON parse error: %s" lineno e :: warns)
        | Ok y ->
          (match bead_of_yaml y with
           | Ok (b, field_warns) ->
             (b :: beads,
              List.rev_append (List.map (Printf.sprintf "line %d: %s" lineno) field_warns) warns)
           | Error e -> (beads, Printf.sprintf "line %d: %s" lineno e :: warns)))
    ([], [])
    (List.mapi (fun i l -> (i + 1, l)) lines)
  |> fun (beads, warns) -> (List.rev beads, List.rev warns)

(** Drop in-file duplicate ids (keep first), warning distinctly so a second
    record with different content isn't confused with a benign "already in the
    tracker" skip. *)
let dedup (beads : bead list) : bead list * string list =
  let seen = Hashtbl.create (List.length beads) in
  List.fold_left
    (fun (kept, warns) b ->
      if Hashtbl.mem seen b.id then
        (kept, Printf.sprintf "duplicate id '%s' in input — kept first, dropped a later record" b.id :: warns)
      else (Hashtbl.add seen b.id (); (b :: kept, warns)))
    ([], []) beads
  |> fun (kept, warns) -> (List.rev kept, List.rev warns)

(** Drop dependency endpoint ids that aren't valid ditz ids (e.g. dotted),
    warning per drop — they can't be real cross-references and would otherwise
    be guaranteed dangling refs. [valid] is the id predicate (Storage.validate_id).
    Non-"blocks" deps (other_deps) are provenance strings, left as-is. *)
let sanitize_edges ~valid (beads : bead list) : bead list * string list =
  List.fold_left
    (fun (acc, warns) b ->
      let good, bad = List.partition valid b.blockers in
      let warns =
        List.fold_left
          (fun w bad_id ->
            Printf.sprintf "%s: dropped blocking edge to invalid id '%s'" b.id bad_id :: w)
          warns bad
      in
      ({ b with blockers = good } :: acc, warns))
    ([], []) beads
  |> fun (acc, warns) -> (List.rev acc, List.rev warns)

(* ---- mapping to ditz ---- *)

let status_of_beads = function
  | "in_progress" | "in-progress" -> In_progress
  | "closed" | "done" -> Closed
  (* "open", "blocked" (blocked is derived from edges), unknown -> unstarted *)
  | _ -> Unstarted

let type_of_beads = function
  | "bug" | "bugfix" | "defect" -> Bugfix
  | "feature" | "enhancement" -> Feature
  | _ -> Task

(** Map a bead to a ditz issue. [blocks] is the reciprocal set (ids this bead
    blocks), reconstructed across the whole import so both edge sides are
    consistent. [reporter_fallback] is used when the bead names no owner. *)
let to_issue ~reporter_fallback ~blocks (b : bead) : issue =
  let who = Option.value b.created_by ~default:"beads-import" in
  let reporter =
    match b.created_by, b.owner with
    | Some n, Some o -> Printf.sprintf "%s <%s>" n o
    | None, Some o -> o
    | Some n, None -> n
    | None, None -> reporter_fallback
  in
  let created_at = Option.value b.created_at ~default:(Issue_ops.now_rfc3339 ()) in
  let status = status_of_beads b.status in
  (* beads has no structured resolution field (only free-text close_reason),
     so every closed issue maps to Fixed; the reason text carries any nuance. *)
  let disposition = if status = Closed then Some Fixed else None in
  (* Provenance for things ditz has no field for, so nothing is silently lost. *)
  (* Everything ditz has no field for, kept auditable rather than dropped. *)
  let provenance =
    List.filter_map (fun x -> x)
      [ Option.map (Printf.sprintf "priority=%d") b.priority;
        (if b.labels = [] then None else Some ("labels=" ^ String.concat "," b.labels));
        Option.map (Printf.sprintf "assignee=%s") b.assignee;
        Option.map (Printf.sprintf "updated_at=%s") b.updated_at;
        (if b.other_deps = [] then None
         else Some ("deps=" ^ String.concat "," (List.map (fun (t, d) -> t ^ ":" ^ d) b.other_deps))) ]
  in
  let ev ?(who = who) time what comment : log_event = { time; who; what; comment } in
  let log_events =
    [ ev created_at "created" "" ]
    @ (if provenance = [] then []
       else [ ev created_at "imported from beads" (String.concat "; " provenance) ])
    @ (match b.notes with
       | Some n when String.trim n <> "" ->
         [ ev (Option.value b.closed_at ~default:created_at) "commented" n ]
       | _ -> [])
    @ (if status = Closed then
         [ ev (Option.value b.closed_at ~default:created_at) "closed: fixed"
             (Option.value b.close_reason ~default:"") ]
       else [])
  in
  {
    id = b.id;
    title = b.title;
    desc = b.desc;
    issue_type = type_of_beads b.itype;
    component = "default";
    release = None;
    reporter;
    status;
    disposition;
    creation_time = created_at;
    references = (match b.external_ref with Some r when r <> "" -> [ r ] | _ -> []);
    log_events;
    blocks;
    blocked_by = b.blockers;
    file_refs = [];
  }

(** Reconstruct the reciprocal "blocks" set for every id from all beads'
    blocker edges (beads only records the blocked side). *)
let reciprocal_blocks (beads : bead list) : (string, string list) Hashtbl.t =
  let tbl = Hashtbl.create (List.length beads) in
  List.iter
    (fun b ->
      List.iter
        (fun blocker ->
          let cur = try Hashtbl.find tbl blocker with Not_found -> [] in
          if not (List.mem b.id cur) then Hashtbl.replace tbl blocker (b.id :: cur))
        b.blockers)
    beads;
  tbl
