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
  acceptance : string option;
  (* Pre-rename id, when [sanitize_ids] had to rewrite it. Kept so the original
     beads id survives in the issue's provenance and stays greppable. *)
  orig_id : string option;
  (* ids that block THIS issue (depends_on_id of each type="blocks" dep) *)
  blockers : string list;
  (* ids of this issue's parents (depends_on_id of each type="parent-child").
     A parent is an epic that is not done until its children are, so each child
     is imported as BLOCKING its parent. The direction was deliberately left
     unmapped until a tracker that actually uses these edges was migrated;
     goals (2026-08) is that tracker, and its staging epic is exactly this
     shape, so the guess is now grounded in real data. *)
  parents : string list;
  (* deps that are neither "blocks" nor "parent-child", as (type,
     depends_on_id): preserved as provenance, not turned into graph edges —
     their direction still isn't safe to guess. predictionbook is flat. *)
  other_deps : (string * string) list;
}

(* ---- tolerant accessors over a parsed JSON object ---- *)

let fields = function `O kvs -> kvs | _ -> []

(* Accessors take a [warns] sink because a field that is PRESENT but of the
   wrong type is data we were handed and threw away -- indistinguishable from
   an absent field once it returns None, which is how `acceptance_criteria: 42`
   used to vanish while the import exited 0. Absent stays silent; present and
   unusable warns. *)
let str_field ?warns kvs k =
  match List.assoc_opt k kvs with
  | Some (`String s) -> Some s
  | None | Some `Null -> None
  | Some _ ->
    (match warns with
     | Some w -> w := Printf.sprintf "field '%s' is present but not a string; value dropped" k :: !w
     | None -> ());
    None

let int_field ?warns kvs k =
  match List.assoc_opt k kvs with
  | Some (`Float f) -> Some (int_of_float f)
  | Some (`String s) ->
    (match int_of_string_opt s with
     | Some _ as v -> v
     | None ->
       (match warns with
        | Some w -> w := Printf.sprintf "field '%s' is not a number ('%s'); value dropped" k s :: !w
        | None -> ());
       None)
  | None | Some `Null -> None
  | Some _ ->
    (match warns with
     | Some w -> w := Printf.sprintf "field '%s' is present but not a number; value dropped" k :: !w
     | None -> ());
    None

let str_list_field ?warns kvs k =
  let note msg = match warns with Some w -> w := msg :: !w | None -> () in
  match List.assoc_opt k kvs with
  | Some (`A items) ->
    List.filter_map
      (function
        | `String s -> Some s
        | _ ->
          note (Printf.sprintf "field '%s' has a non-string entry; entry dropped" k);
          None)
      items
  | None | Some `Null -> []
  | Some _ ->
    note (Printf.sprintf "field '%s' is present but not a list; value dropped" k);
    []

(* beads deps live on the dependent issue: {depends_on_id, type}. "blocks"
   becomes a graph blocker and "parent-child" a parent edge (depends_on_id is
   the parent, recorded on the child); every other type is surfaced as
   provenance rather than silently becoming an edge with a guessed direction.
   Returns (blockers, parents, other_deps, warnings) — a present-but-malformed
   `dependencies` field warns rather than vanishing, since a dropped edge is
   real data loss. *)
let parse_deps kvs =
  match List.assoc_opt "dependencies" kvs with
  | None | Some `Null -> ([], [], [], [])
  | Some (`A items) ->
    List.fold_left
      (fun (blk, par, other, warns) item ->
        let f = fields item in
        match str_field f "type", str_field f "depends_on_id" with
        | Some "blocks", Some dep -> (dep :: blk, par, other, warns)
        | Some ("parent-child" | "parent_child"), Some dep -> (blk, dep :: par, other, warns)
        | Some t, Some dep -> (blk, par, (t, dep) :: other, warns)
        | _ -> (blk, par, other, "dependency entry missing type/depends_on_id" :: warns))
      ([], [], [], []) items
    |> fun (blk, par, other, w) -> (List.rev blk, List.rev par, List.rev other, List.rev w)
  | Some _ -> ([], [], [], [ "`dependencies` is not an array; dependencies ignored" ])

(* Returns the bead plus any field-level warnings (e.g. malformed deps). *)
let bead_of_yaml (y : Yaml.value) : (bead * string list, string) result =
  let kvs = fields y in
  let warns = ref [] in
  let str = str_field ~warns kvs and strs = str_list_field ~warns kvs in
  match str "id", str "title" with
  | None, _ -> Error "line has no string id"
  | _, None -> Error "line has no string title"
  | Some id, Some title ->
    let blockers, parents, other_deps, dep_warns = parse_deps kvs in
    (* The record is bound BEFORE the warning list is read. Building both inside
       one tuple would leave it to OCaml's unspecified (in practice
       right-to-left) argument evaluation order, which read [warns] before the
       field accessors had run and silently discarded every field warning. *)
    let bead =
      {
        id; title;
        desc = Option.value (str "description") ~default:"";
        status = Option.value (str "status") ~default:"open";
        priority = int_field ~warns kvs "priority";
        itype = Option.value (str "issue_type") ~default:"task";
        owner = str "owner";
        assignee = str "assignee";
        created_by = str "created_by";
        created_at = str "created_at";
        updated_at = str "updated_at";
        closed_at = str "closed_at";
        close_reason = str "close_reason";
        external_ref = str "external_ref";
        labels = strs "labels";
        notes = str "notes";
        acceptance = str "acceptance_criteria";
        orig_id = None;
        blockers;
        parents;
        other_deps;
      }
    in
    let field_warns = List.rev !warns @ dep_warns in
    Ok (bead, List.map (Printf.sprintf "%s: %s" id) field_warns)

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

(* Provenance is written as "k=v; k=v", so segment on "; " and compare whole
   segments. A substring test would let beads_id=g-1 match a record whose real
   provenance says beads_id=g-10. *)
let split_on_sub sep str =
  let sl = String.length sep and n = String.length str in
  let rec go start i acc =
    if i + sl > n then List.rev (String.sub str start (n - start) :: acc)
    else if String.sub str i sl = sep then go (i + sl) (i + sl) (String.sub str start (i - start) :: acc)
    else go start (i + 1) acc
  in
  if sl = 0 || n = 0 then [ str ] else go 0 0 []

(** Does the issue already in the tracker descend from beads issue [beads_id]?
    The beads_id= provenance written by a previous import is the only available
    proof, and it is what separates a benign idempotent re-import of a renamed
    issue from an unrelated occupant of the same id. *)
let issue_has_beads_id (i : issue) (beads_id : string) : bool =
  let want = "beads_id=" ^ beads_id in
  List.exists
    (fun (e : log_event) ->
      List.exists (fun seg -> String.trim seg = want) (split_on_sub "; " e.comment))
    i.log_events

(** Rewrite ids ditz cannot store into ones it can, across an issue's own id
    AND every edge endpoint, so the graph stays connected. beads mints dotted
    child ids ("goals-53u.1") that ditz rejects, and dropping those issues
    loses whole subtrees; renaming keeps them, and the pre-rename id is carried
    on [orig_id] so it still appears in the issue's provenance.

    A rename is lossless and yields a NOTICE. A rename that cannot be granted
    because the target id is already spoken for is not: the issue would be
    silently swallowed by whoever holds the id. Those WARN and the issue is not
    imported, so an operator has to resolve it rather than discover the loss
    later. An id is spoken for if another record in this import owns it
    natively, if an earlier rename claimed it, or if [taken] says the
    destination tracker already holds an unrelated issue under it.

    Endpoints are rewritten through the same function whether or not the record
    they name is in this file, so an edge into an issue imported by an earlier
    run still lands on that issue's renamed id. *)
let sanitize_id id =
  String.map
    (function ('a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_') as c -> c | _ -> '-')
    id

let sanitize_ids ?(taken = fun ~orig:_ ~renamed:_ -> false)
    ?(resolve_external = fun _ -> None) (beads : bead list) :
    bead list * string list * string list =
  let notices = ref [] and warns = ref [] in
  let n = List.length beads in
  let rename = Hashtbl.create n in
  (* Ids already spoken for: every record that can keep its own id owns it. *)
  let claimed = Hashtbl.create n in
  List.iter (fun b -> if sanitize_id b.id = b.id then Hashtbl.replace claimed b.id b.id) beads;
  let dropped = Hashtbl.create 4 in
  List.iter
    (fun b ->
      let s = sanitize_id b.id in
      if s <> b.id then
        match Hashtbl.find_opt claimed s with
        | Some owner when owner <> b.id ->
          warns :=
            Printf.sprintf
              "id '%s' cannot be renamed to '%s': '%s' already owns that id; issue not imported"
              b.id s owner
            :: !warns;
          Hashtbl.replace dropped b.id ()
        | Some _ ->
          (* The same record id twice: a plain duplicate, which is dedup's
             business. The rename granted on the first occurrence applies to
             both, so nothing to do here and nothing to report twice. *)
          ()
        | None ->
          (* [taken] is asked about THIS bead, not just the destination id.
             "the tracker's occupant is really me" is a claim about one source
             id: a destination-wide question answers yes if ANY bead in the file
             could be the occupant, which handed the id to whichever bead came
             first and refused the one that actually owned it. *)
          if taken ~orig:b.id ~renamed:s then begin
            warns :=
              Printf.sprintf
                "id '%s' cannot be renamed to '%s': an unrelated issue already holds that id in \
                 the tracker; issue not imported"
                b.id s
              :: !warns;
            Hashtbl.replace dropped b.id ()
          end
          else begin
            notices :=
              Printf.sprintf "renamed id '%s' -> '%s' (ditz ids allow only [A-Za-z0-9_-])" b.id s
              :: !notices;
            Hashtbl.add rename b.id s;
            Hashtbl.replace claimed s b.id
          end)
    beads;
  (* An endpoint naming a record in this file follows that record's rename.
     One naming anything else is handed to [resolve_external], which is the only
     thing that can see the tracker. Blindly sanitizing it instead would wire
     the edge to whatever issue happens to sit on the sanitized id -- an edge to
     beads "x.y" would silently attach to an unrelated ditz "x-y". Unresolved
     ids are left alone, so the caller's existence check drops them and warns. *)
  let map_id id =
    match Hashtbl.find_opt rename id with
    | Some s -> s
    | None -> ( match resolve_external id with Some s -> s | None -> id)
  in
  let beads =
    List.filter (fun b -> not (Hashtbl.mem dropped b.id)) beads
    |> List.map (fun b ->
           let new_id = map_id b.id in
           {
             b with
             id = new_id;
             orig_id = (if new_id = b.id then b.orig_id else Some b.id);
             blockers = List.map map_id b.blockers;
             parents = List.map map_id b.parents;
             other_deps = List.map (fun (t, d) -> (t, map_id d)) b.other_deps;
           })
  in
  (beads, List.rev !notices, List.rev !warns)

(** Drop dependency endpoints that will not exist after the import, warning per
    drop. [known] answers "will an issue with this id exist when we are done" --
    it must cover both the records being imported and what the tracker already
    holds, because an import is incremental, not a fresh world. A retained edge
    to a non-existent id is worse than a dropped one: `ditz deps --check`
    rejects the whole graph as DANGLING, so the importer would be manufacturing
    invalid data while reporting success.

    Non-"blocks"/"parent-child" deps (other_deps) are provenance strings, not
    edges, and are left as-is. *)
let sanitize_edges ~known (beads : bead list) : bead list * string list =
  List.fold_left
    (fun (acc, warns) b ->
      (* An issue cannot block or parent itself. beads permits the record;
         ditz's own `deps --check` calls it a CYCLE, so importing it would again
         mean manufacturing a graph the tool rejects. *)
      let self_blockers, blockers = List.partition (fun d -> d = b.id) b.blockers in
      let self_parents, parents = List.partition (fun d -> d = b.id) b.parents in
      let b = { b with blockers; parents } in
      let warns =
        List.fold_left
          (fun w _ -> Printf.sprintf "%s: dropped self-referential edge" b.id :: w)
          warns
          (self_blockers @ self_parents)
      in
      let good, bad = List.partition known b.blockers in
      let good_parents, bad_parents = List.partition known b.parents in
      let warns =
        List.fold_left
          (fun w bad_id ->
            Printf.sprintf "%s: dropped blocking edge to unknown id '%s'" b.id bad_id :: w)
          warns bad
      in
      let warns =
        List.fold_left
          (fun w bad_id ->
            Printf.sprintf "%s: dropped parent edge to unknown id '%s'" b.id bad_id :: w)
          warns bad_parents
      in
      ({ b with blockers = good; parents = good_parents } :: acc, warns))
    ([], []) beads
  |> fun (acc, warns) -> (List.rev acc, List.rev warns)

(* ---- mapping to ditz ---- *)

(* [None] means beads used a status ditz has no counterpart for. It still maps
   to Unstarted, but the original is kept in provenance rather than erased --
   "deferred" and "open" are not the same statement about an issue. Matching is
   case-insensitive so "Open" is not mistaken for something exotic. *)
let status_of_beads_opt s =
  match String.lowercase_ascii (String.trim s) with
  | "in_progress" | "in-progress" -> Some In_progress
  | "closed" | "done" -> Some Closed
  (* "blocked" is derived from edges in ditz, so it is a faithful Unstarted *)
  | "open" | "blocked" -> Some Unstarted
  | _ -> None

let status_of_beads s = Option.value (status_of_beads_opt s) ~default:Unstarted

(* Recognized beads types. [None] means ditz has no counterpart, so the label
   is unrecoverable after mapping and belongs in provenance -- unlike an alias
   such as "bug" -> bugfix, which renames without losing anything. *)
let type_of_beads_opt s =
  match String.lowercase_ascii (String.trim s) with
  | "bug" | "bugfix" | "defect" -> Some Bugfix
  | "feature" | "enhancement" -> Some Feature
  | "task" -> Some Task
  | _ -> None

let type_of_beads s = Option.value (type_of_beads_opt s) ~default:Task

(** Map a bead to a ditz issue. [blocks] is the reciprocal set (ids this bead
    blocks), reconstructed across the whole import so both edge sides are
    consistent. [reporter_fallback] is used when the bead names no owner. *)
(* Order-preserving dedup. Hashed rather than List.mem so a hub issue with
   hundreds of edges stays linear. *)
let dedup_strings l =
  let seen = Hashtbl.create (List.length l) in
  List.rev
    (List.fold_left
       (fun acc x ->
         if Hashtbl.mem seen x then acc
         else begin
           Hashtbl.add seen x ();
           x :: acc
         end)
       [] l)

(* beads' acceptance_criteria has no ditz counterpart, and ditz keeps its model
   deliberately small, so the prose is folded into the description rather than
   growing the schema for one importer. Losing it is not an option: it is the
   definition of done. *)
let desc_with_acceptance (b : bead) =
  match b.acceptance with
  | Some a when String.trim a <> "" ->
    (* [a] is kept verbatim; the trim only answers "is this blank". *)
    if String.trim b.desc = "" then "Acceptance: " ^ a else b.desc ^ "\n\nAcceptance: " ^ a
  | _ -> b.desc

let to_issue ~reporter_fallback ~blocks ?(blocked_by_extra = []) (b : bead) : issue =
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
        Option.map (Printf.sprintf "beads_id=%s") b.orig_id;
        (* ditz has three types; beads has more. "epic" and "chore" both land
           on Task, so without this the original label is unrecoverable. *)
        (if type_of_beads_opt b.itype = None then Some (Printf.sprintf "beads_type=%s" b.itype)
         else None);
        (if status_of_beads_opt b.status = None then
           Some (Printf.sprintf "beads_status=%s" b.status)
         else None);
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
    desc = desc_with_acceptance b;
    issue_type = type_of_beads b.itype;
    component = "default";
    release = None;
    reporter;
    status;
    disposition;
    creation_time = created_at;
    references = (match b.external_ref with Some r when r <> "" -> [ r ] | _ -> []);
    log_events;
    (* A child blocks its parent: the epic is not done until its children are. *)
    blocks = dedup_strings (blocks @ b.parents);
    blocked_by = dedup_strings (b.blockers @ blocked_by_extra);
    file_refs = [];
  }

(** Children of each parent id, from the parent-child edges recorded on the
    children. Feeds the parent's [blocked_by], the reciprocal of the child's
    [blocks]. File order is preserved so the epic reads in the order its
    children were created. *)
let children_by_parent (beads : bead list) : (string, string list) Hashtbl.t =
  let tbl = Hashtbl.create (List.length beads) in
  (* Accumulate reversed with a membership set, then reverse once: appending
     with @ inside the loop was quadratic in the number of children. *)
  let seen = Hashtbl.create (List.length beads) in
  List.iter
    (fun b ->
      List.iter
        (fun parent ->
          if not (Hashtbl.mem seen (parent, b.id)) then begin
            Hashtbl.add seen (parent, b.id) ();
            let cur = Option.value (Hashtbl.find_opt tbl parent) ~default:[] in
            Hashtbl.replace tbl parent (b.id :: cur)
          end)
        b.parents)
    beads;
  Hashtbl.iter (fun k v -> Hashtbl.replace tbl k (List.rev v)) (Hashtbl.copy tbl);
  tbl

(** Reconstruct the reciprocal "blocks" set for every id from all beads'
    blocker edges (beads only records the blocked side). *)
let reciprocal_blocks (beads : bead list) : (string, string list) Hashtbl.t =
  let tbl = Hashtbl.create (List.length beads) in
  let seen = Hashtbl.create (List.length beads) in
  List.iter
    (fun b ->
      List.iter
        (fun blocker ->
          if not (Hashtbl.mem seen (blocker, b.id)) then begin
            Hashtbl.add seen (blocker, b.id) ();
            let cur = Option.value (Hashtbl.find_opt tbl blocker) ~default:[] in
            Hashtbl.replace tbl blocker (b.id :: cur)
          end)
        b.blockers)
    beads;
  Hashtbl.iter (fun k v -> Hashtbl.replace tbl k (List.rev v)) (Hashtbl.copy tbl);
  tbl
