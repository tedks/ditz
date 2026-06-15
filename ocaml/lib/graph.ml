(** Dependency-graph derivations over the blocked_by relation. Pure; no I/O.

    Edge direction: "A blocks B" iff B.blocked_by contains A. We treat
    [blocked_by] as authoritative — the reciprocal [blocks] list can diverge in
    hand-edited or sync-merged files, and "what am I waiting on" is the question
    that actually gates work. All traversals are cycle-safe via a visited set;
    nothing in the data model prevents cycles (see PR 2 for detection). *)

open Types

module SS = Set.Make (String)

(** Forward "blocks" adjacency: id -> ids it directly blocks. Built from every
    issue's [blocked_by] (B.blocked_by contains A  =>  A blocks B). *)
let blocks_adjacency (issues : issue list) : (string, string list) Hashtbl.t =
  let adj = Hashtbl.create (max 16 (List.length issues * 2)) in
  List.iter
    (fun (b : issue) ->
      List.iter
        (fun a ->
          let cur = try Hashtbl.find adj a with Not_found -> [] in
          Hashtbl.replace adj a (b.id :: cur))
        b.blocked_by)
    issues;
  adj

(** Set of ids transitively blocked by [start], EXCLUDING [start] itself (even
    when a cycle leads back to it). Cycle-safe. *)
let transitively_blocked adj start =
  let rec go acc id =
    let succs = try Hashtbl.find adj id with Not_found -> [] in
    List.fold_left
      (fun acc s -> if SS.mem s acc then acc else go (SS.add s acc) s)
      acc succs
  in
  SS.remove start (go SS.empty start)

(** Returns [fun id -> n], where n is the count of currently-OPEN issues that
    [id] transitively unblocks. The headline `ready` heuristic: a higher score
    means closing this issue frees more downstream work. Adjacency and the
    open-set are built once; each lookup is a bounded DFS. *)
let unblock_score (issues : issue list) : string -> int =
  let adj = blocks_adjacency issues in
  let open_ids =
    List.fold_left
      (fun acc (i : issue) -> if i.status <> Closed then SS.add i.id acc else acc)
      SS.empty issues
  in
  fun id ->
    transitively_blocked adj id
    |> SS.elements
    |> List.filter (fun x -> SS.mem x open_ids)
    |> List.length

(** Sorted list of ids transitively blocked by [id] (excluding [id]); a
    set-free convenience for callers outside this module. *)
let transitively_blocks_list (issues : issue list) id =
  SS.elements (transitively_blocked (blocks_adjacency issues) id)

(* ---- Integrity checks (L1 prevention, L2 diagnostics) ---- *)

(** Would adding "[blocker] blocks [blocked]" close a cycle? True if it's a
    self-edge, or [blocked] already transitively blocks [blocker] (so the new
    forward edge blocker->blocked completes a loop). *)
let blocks_would_cycle (issues : issue list) ~blocker ~blocked =
  blocker = blocked
  || SS.mem blocker (transitively_blocked (blocks_adjacency issues) blocked)

(** Ids referenced by some blocks/blocked_by that have no corresponding issue,
    as (referencing_id, missing_id, relation) where relation is "blocks" or
    "blocked_by". *)
let dangling_refs (issues : issue list) =
  let known = List.fold_left (fun acc (i : issue) -> SS.add i.id acc) SS.empty issues in
  List.concat_map
    (fun (i : issue) ->
      let miss rel ids =
        List.filter_map (fun r -> if SS.mem r known then None else Some (i.id, r, rel)) ids
      in
      miss "blocks" i.blocks @ miss "blocked_by" i.blocked_by)
    issues

(** Reciprocity violations: a "blocks" edge with no matching "blocked_by" on the
    other side, or vice versa, as (blocker, blocked) pairs asserted on only one
    side. (`blocks` keeps both sides in sync, but hand-edits and merges can
    break it.) Dangling refs are excluded — reported separately. *)
let one_sided_edges (issues : issue list) =
  let known = List.fold_left (fun acc (i : issue) -> SS.add i.id acc) SS.empty issues in
  let tbl = Hashtbl.create (List.length issues) in
  List.iter (fun (i : issue) -> Hashtbl.replace tbl i.id i) issues;
  let blocked_by_of id = match Hashtbl.find_opt tbl id with Some i -> i.blocked_by | None -> [] in
  let blocks_of id = match Hashtbl.find_opt tbl id with Some i -> i.blocks | None -> [] in
  let from_blocks =
    List.concat_map
      (fun (i : issue) ->
        List.filter_map
          (fun b -> if SS.mem b known && not (List.mem i.id (blocked_by_of b))
                    then Some (i.id, b) else None)
          i.blocks)
      issues
  in
  let from_blocked_by =
    List.concat_map
      (fun (i : issue) ->
        List.filter_map
          (fun a -> if SS.mem a known && not (List.mem i.id (blocks_of a))
                    then Some (a, i.id) else None)
          i.blocked_by)
      issues
  in
  List.sort_uniq compare (from_blocks @ from_blocked_by)

(** Cycles in the blocks graph, as lists of ids. Tarjan SCC: any component with
    more than one node, or a single node with a self-edge, is a cycle. *)
let find_cycles (issues : issue list) : string list list =
  let adj = blocks_adjacency issues in
  let succ id = try Hashtbl.find adj id with Not_found -> [] in
  let nodes =
    List.fold_left
      (fun acc (i : issue) ->
        let acc = SS.add i.id acc in
        List.fold_left (fun acc s -> SS.add s acc) acc (succ i.id))
      SS.empty issues
    |> SS.elements
  in
  let index = Hashtbl.create 64 and low = Hashtbl.create 64 in
  let onstack = Hashtbl.create 64 in
  let stack = ref [] and counter = ref 0 and sccs = ref [] in
  let rec strongconnect v =
    Hashtbl.replace index v !counter;
    Hashtbl.replace low v !counter;
    incr counter;
    stack := v :: !stack;
    Hashtbl.replace onstack v true;
    List.iter
      (fun w ->
        if not (Hashtbl.mem index w) then begin
          strongconnect w;
          Hashtbl.replace low v (min (Hashtbl.find low v) (Hashtbl.find low w))
        end
        else if Hashtbl.find_opt onstack w = Some true then
          Hashtbl.replace low v (min (Hashtbl.find low v) (Hashtbl.find index w)))
      (succ v);
    if Hashtbl.find low v = Hashtbl.find index v then begin
      let rec pop acc =
        match !stack with
        | [] -> acc
        | w :: rest ->
          stack := rest;
          Hashtbl.replace onstack w false;
          let acc = w :: acc in
          if w = v then acc else pop acc
      in
      sccs := pop [] :: !sccs
    end
  in
  List.iter (fun v -> if not (Hashtbl.mem index v) then strongconnect v) nodes;
  List.filter
    (fun scc ->
      match scc with
      | [ single ] -> List.mem single (succ single)
      | _ :: _ :: _ -> true
      | [] -> false)
    !sccs
