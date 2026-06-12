(** Tests for the pure three-way issue merge used by sync conflict resolution. *)

open Ditz
open Types

let mk ?(id = "x1") ?(title = "T") ?(desc = "") ?(status = Unstarted)
    ?(disposition = None) ?(log_events = []) ?(blocks = [])
    ?(references = []) ?(creation_time = "2026-01-01T00:00:00Z") () =
  { id; title; desc; issue_type = Task; component = "c"; release = None;
    reporter = "R <r@example.com>"; status; disposition; creation_time;
    references; log_events; blocks; blocked_by = []; file_refs = [] }

let ev time what comment = { time; who = "W <w@example.com>"; what; comment }

let ok = function
  | Ok v -> v
  | Error field -> failwith ("unexpected conflict on field: " ^ field)

let () =
  let e0 = ev "2026-06-01T00:00:00Z" "created" "" in
  let e1 = ev "2026-06-02T00:00:00Z" "commented" "from ours" in
  let e2 = ev "2026-06-03T00:00:00Z" "commented" "from theirs" in

  (* 1. Comment on both sides: union, deduped, time-sorted *)
  let base = mk ~log_events:[ e0 ] () in
  let ours = mk ~log_events:[ e0; e1 ] () in
  let theirs = mk ~log_events:[ e0; e2 ] () in
  let m = ok (Merge.merge_issues ~base:(Some base) ~ours ~theirs) in
  assert (m.log_events = [ e0; e1; e2 ]);
  Printf.printf "PASS: log_events union\n";

  (* 2. Status LWW by latest activity: theirs acted later -> theirs wins *)
  let ours = mk ~status:Closed ~disposition:(Some Fixed) ~log_events:[ e0; e1 ] () in
  let theirs = mk ~status:In_progress ~log_events:[ e0; e2 ] () in
  let m = ok (Merge.merge_issues ~base:(Some base) ~ours ~theirs) in
  assert (m.status = In_progress && m.disposition = None);
  (* ...and the mirror: ours acted later -> ours wins *)
  let ours' = mk ~status:Closed ~disposition:(Some Fixed) ~log_events:[ e0; e2 ] () in
  let theirs' = mk ~status:In_progress ~log_events:[ e0; e1 ] () in
  let m' = ok (Merge.merge_issues ~base:(Some base) ~ours:ours' ~theirs:theirs') in
  assert (m'.status = Closed && m'.disposition = Some Fixed);
  Printf.printf "PASS: status last-write-wins\n";

  (* 2b. A side that merely commented must NOT revert the other side's close:
     status is three-way picked before any LWW (council round 3) *)
  let closer =
    mk ~status:Closed ~disposition:(Some Fixed)
      ~log_events:[ e0; ev "2026-06-02T00:00:00Z" "closed: fixed" "" ] ()
  in
  let commenter = mk ~log_events:[ e0; e2 ] () (* newer activity, base status *) in
  let m = ok (Merge.merge_issues ~base:(Some base) ~ours:closer ~theirs:commenter) in
  assert (m.status = Closed && m.disposition = Some Fixed);
  let m' = ok (Merge.merge_issues ~base:(Some base) ~ours:commenter ~theirs:closer) in
  assert (m'.status = Closed && m'.disposition = Some Fixed);
  Printf.printf "PASS: comment does not revert close\n";

  (* 3. Title changed on one side only: change is kept *)
  let m =
    ok (Merge.merge_issues ~base:(Some (mk ()))
          ~ours:(mk ~title:"New title" ()) ~theirs:(mk ()))
  in
  assert (m.title = "New title");
  Printf.printf "PASS: one-sided title change\n";

  (* 4. Title changed on both sides: conflict, never guess *)
  (match Merge.merge_issues ~base:(Some (mk ()))
           ~ours:(mk ~title:"A" ()) ~theirs:(mk ~title:"B" ()) with
   | Error "title" -> ()
   | Error f -> failwith ("expected title conflict, got: " ^ f)
   | Ok _ -> failwith "expected conflict for double title change");
  Printf.printf "PASS: two-sided title change conflicts\n";

  (* 5. blocks: additions kept, deletions honored, no resurrection *)
  let base = mk ~blocks:[ "a"; "b" ] () in
  let ours = mk ~blocks:[ "a"; "b"; "c" ] () in
  let theirs = mk ~blocks:[ "b" ] () in
  let m = ok (Merge.merge_issues ~base:(Some base) ~ours ~theirs) in
  assert (m.blocks = [ "b"; "c" ]);
  Printf.printf "PASS: three-way list merge (no resurrection)\n";

  (* 5b. Exact LWW tie (both changed, identical latest event time) keeps ours *)
  let tie_ev = ev "2026-06-05T00:00:00Z" "changed" "" in
  let m =
    ok (Merge.merge_issues ~base:(Some base)
          ~ours:(mk ~status:Closed ~disposition:(Some Fixed) ~log_events:[ e0; tie_ev ] ())
          ~theirs:(mk ~status:Paused ~log_events:[ e0; tie_ev ] ()))
  in
  assert (m.status = Closed && m.disposition = Some Fixed);
  Printf.printf "PASS: LWW tie keeps ours\n";

  (* 5c. Duplicate entries collapse: list merge is a set merge *)
  let m =
    ok (Merge.merge_issues ~base:None
          ~ours:(mk ~blocks:[ "a"; "a" ] ()) ~theirs:(mk ~blocks:[ "a"; "c" ] ()))
  in
  assert (m.blocks = [ "a"; "c" ]);
  Printf.printf "PASS: duplicate entries collapse\n";

  (* 6. Without a base, lists fall back to union *)
  let m =
    ok (Merge.merge_issues ~base:None
          ~ours:(mk ~references:[ "r1" ] ()) ~theirs:(mk ~references:[ "r2" ] ()))
  in
  assert (m.references = [ "r1"; "r2" ]);
  Printf.printf "PASS: baseless union\n";

  (* 7. Serialization round trip *)
  let i = mk ~log_events:[ e0; e1 ] ~blocks:[ "z" ] () in
  (match Merge.issue_to_string i with
   | Error (`Msg e) -> failwith e
   | Ok s ->
     (match Merge.issue_of_string s with
      | Ok i' -> assert (i' = i)
      | Error (`Msg e) -> failwith e));
  Printf.printf "PASS: round trip\n";

  (* 8. Large issues serialize rather than raising (bounded emitter buffer) *)
  let big = mk ~desc:(String.make 300_000 'x') () in
  (match Merge.issue_to_string big with
   | Ok s -> assert (String.length s > 300_000)
   | Error (`Msg e) -> failwith ("large issue should serialize: " ^ e));
  Printf.printf "PASS: large issue serializes\n";

  Printf.printf "\nAll merge tests passed!\n"
