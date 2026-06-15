(** Tests for graph-derived ready scoring (cycle-safe transitive unblock count). *)

open Ditz

(* Build an issue with given id, status, and blocked_by edges. *)
let mk ?(status = Types.Unstarted) ?(blocked_by = []) id : Types.issue =
  { Types.id; title = id; desc = ""; issue_type = Types.Task; component = "c";
    release = None; reporter = "R <r@e.co>"; status; disposition = None;
    creation_time = "2026-01-01T00:00:00Z"; references = []; log_events = [];
    blocks = []; blocked_by; file_refs = [] }

let () =
  (* Chain: a blocks b blocks c blocks d  (encoded via blocked_by).
     a transitively unblocks b,c,d = 3; b -> 2; c -> 1; d -> 0. *)
  let chain = [
    mk "a";
    mk "b" ~blocked_by:["a"];
    mk "c" ~blocked_by:["b"];
    mk "d" ~blocked_by:["c"];
  ] in
  let s = Graph.unblock_score chain in
  assert (s "a" = 3);
  assert (s "b" = 2);
  assert (s "c" = 1);
  assert (s "d" = 0);
  print_endline "PASS: chain";

  (* Closed issues don't count toward the score. Close c: a now unblocks b,d
     (c is closed) = 2; b unblocks d (through closed c, still reachable) = 1. *)
  let chain_c_closed = [
    mk "a";
    mk "b" ~blocked_by:["a"];
    mk "c" ~status:Types.Closed ~blocked_by:["b"];
    mk "d" ~blocked_by:["c"];
  ] in
  let s = Graph.unblock_score chain_c_closed in
  assert (s "a" = 2);   (* b, d open; c closed not counted *)
  assert (s "b" = 1);   (* d *)
  print_endline "PASS: closed nodes excluded from count";

  (* Diamond: a blocks b and c; b and c both block d. a unblocks {b,c,d} = 3
     (d counted once, not twice). *)
  let diamond = [
    mk "a";
    mk "b" ~blocked_by:["a"];
    mk "c" ~blocked_by:["a"];
    mk "d" ~blocked_by:["b"; "c"];
  ] in
  let s = Graph.unblock_score diamond in
  assert (s "a" = 3);
  assert (s "b" = 1);
  assert (s "d" = 0);
  print_endline "PASS: diamond (no double count)";

  (* Cycle: a blocks b, b blocks a. Must terminate. Each unblocks the other
     (and not itself): score 1 each. *)
  let cycle = [
    mk "a" ~blocked_by:["b"];
    mk "b" ~blocked_by:["a"];
  ] in
  let s = Graph.unblock_score cycle in
  assert (s "a" = 1);   (* unblocks b, not itself *)
  assert (s "b" = 1);
  print_endline "PASS: cycle terminates, excludes self";

  (* Disconnected / flat: no edges -> every score 0. *)
  let flat = [ mk "x"; mk "y"; mk "z" ] in
  let s = Graph.unblock_score flat in
  assert (s "x" = 0 && s "y" = 0 && s "z" = 0);
  print_endline "PASS: flat graph all zero";

  (* Dangling edge target (blocked_by an id not in the set) doesn't crash and
     doesn't inflate scores. *)
  let dangling = [ mk "a" ~blocked_by:["ghost"]; mk "b" ~blocked_by:["a"] ] in
  let s = Graph.unblock_score dangling in
  assert (s "a" = 1);        (* a unblocks b *)
  assert (s "ghost" = 2);    (* ghost (unknown) transitively unblocks a then b *)
  print_endline "PASS: dangling target tolerated";

  (* ---- integrity checks (L1/L2) ---- *)

  (* blocks_would_cycle: a->b->c exists; c blocks a closes a loop; self too;
     an existing edge adds no new cycle; an unrelated node doesn't. *)
  let abc = [ mk "a"; mk "b" ~blocked_by:["a"]; mk "c" ~blocked_by:["b"] ] in
  assert (Graph.blocks_would_cycle abc ~blocker:"c" ~blocked:"a");
  assert (Graph.blocks_would_cycle abc ~blocker:"a" ~blocked:"a");
  assert (not (Graph.blocks_would_cycle abc ~blocker:"a" ~blocked:"c"));
  assert (not (Graph.blocks_would_cycle (mk "d" :: abc) ~blocker:"d" ~blocked:"a"));
  print_endline "PASS: blocks_would_cycle";

  (* find_cycles: a<->b is a cycle; the acyclic chain has none. *)
  let cyc = [ mk "a" ~blocked_by:["b"]; mk "b" ~blocked_by:["a"]; mk "x" ] in
  (match Graph.find_cycles cyc with
   | [ c ] -> assert (List.sort compare c = ["a"; "b"])
   | other -> failwith (Printf.sprintf "expected one cycle, got %d" (List.length other)));
  assert (Graph.find_cycles abc = []);
  (* self-loop is a 1-node cycle *)
  (match Graph.find_cycles [ mk "s" ~blocked_by:["s"] ] with
   | [ ["s"] ] -> () | _ -> failwith "expected self-loop cycle");
  (* a diamond is NOT a cycle (no false positive) *)
  assert (Graph.find_cycles diamond = []);
  (* two disjoint cycles -> two components *)
  let two = [ mk "p" ~blocked_by:["q"]; mk "q" ~blocked_by:["p"];
              mk "r" ~blocked_by:["t"]; mk "t" ~blocked_by:["r"] ] in
  assert (List.length (Graph.find_cycles two) = 2);
  print_endline "PASS: find_cycles";

  (* dangling_refs: blocked_by an unknown id is reported; clean graph isn't. *)
  (match Graph.dangling_refs [ mk "a" ~blocked_by:["ghost"] ] with
   | [ ("a", "ghost", "blocked_by") ] -> ()
   | _ -> failwith "expected one dangling blocked_by ref");
  assert (Graph.dangling_refs abc = []);
  print_endline "PASS: dangling_refs";

  (* one_sided_edges: a.blocks=[b] but b.blocked_by lacks a -> reported. A
     fully reciprocal pair (both sides recorded, as the `blocks` command keeps
     them) is clean. NB: `mk` sets only blocked_by, so abc is itself one-sided
     by construction — exactly what this check flags. *)
  let one_sided = [ { (mk "a") with Types.blocks = ["b"] }; mk "b" ] in
  assert (Graph.one_sided_edges one_sided = [ ("a", "b") ]);
  let reciprocal = [ { (mk "a") with Types.blocks = ["b"] }; mk "b" ~blocked_by:["a"] ] in
  assert (Graph.one_sided_edges reciprocal = []);
  print_endline "PASS: one_sided_edges";

  print_endline "\nAll graph tests passed!"
