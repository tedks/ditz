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
