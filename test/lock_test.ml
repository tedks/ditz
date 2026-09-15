(** Tests for the tracker write lock (Storage.with_write_lock). *)

open Ditz

let make_temp_dir prefix =
  let path = Filename.temp_file prefix "" in
  Sys.remove path; Unix.mkdir path 0o700; path

let contains hay nee =
  let hl = String.length hay and nl = String.length nee in
  let rec go i = i + nl <= hl && (String.sub hay i nl = nee || go (i + 1)) in
  nl = 0 || go 0

let () =
  (* A filesystem-backend tracker outside any git repository (dune runs tests
     inside the ditz checkout, whose own tracker must not be touched). *)
  let dir = make_temp_dir "ditz_lock" in
  at_exit (fun () -> ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir))));
  Sys.chdir dir;
  Unix.mkdir ".ditz" 0o755;

  (* uncontended: runs and returns the body's value *)
  assert (Storage.with_write_lock (fun () -> 42) = Ok 42);
  print_endline "PASS: uncontended lock runs the body";

  (* a second process holding the lock makes us wait, then give up with a
     retry hint once DITZ_LOCK_TIMEOUT passes -- without running the body *)
  let hold ~seconds ~crash =
    match Unix.fork () with
    | 0 ->
      ignore (Storage.with_write_lock (fun () ->
        Unix.sleepf seconds;
        (* crash: exit while holding the lock, no cleanup *)
        if crash then Unix._exit 3));
      Unix._exit 0
    | pid -> pid
  in
  let child = hold ~seconds:2.0 ~crash:false in
  Unix.sleepf 0.4;
  Unix.putenv "DITZ_LOCK_TIMEOUT" "0.3";
  let ran = ref false in
  (match Storage.with_write_lock (fun () -> ran := true) with
   | Ok () -> failwith "expected the lock to time out while another process holds it"
   | Error (`Msg m) -> assert (contains m "another ditz command"));
  assert (not !ran);
  print_endline "PASS: contended lock times out with a retry hint, body not run";

  (* with a longer timeout it waits for the holder and then runs *)
  Unix.putenv "DITZ_LOCK_TIMEOUT" "10";
  assert (Storage.with_write_lock (fun () -> "after") = Ok "after");
  ignore (Unix.waitpid [] child);
  print_endline "PASS: waits for the holder, then runs";

  (* a holder that dies mid-command cannot leave a stale lock *)
  let crasher = hold ~seconds:0.5 ~crash:true in
  Unix.sleepf 0.2;
  Unix.putenv "DITZ_LOCK_TIMEOUT" "5";
  assert (Storage.with_write_lock (fun () -> ()) = Ok ());
  ignore (Unix.waitpid [] crasher);
  print_endline "PASS: a crashed holder releases the lock";

  (* no tracker at all: nothing to lock, body still runs *)
  Sys.chdir (make_temp_dir "ditz_nolock");
  assert (Storage.with_write_lock (fun () -> 7) = Ok 7);
  print_endline "PASS: no tracker, no lock";
  print_endline "\nAll lock tests passed!"
