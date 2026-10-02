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
  let hold ~issue_dir ~crash =
    let ready_r, ready_w = Unix.pipe () in
    let release_r, release_w = Unix.pipe () in
    match Unix.fork () with
    | 0 ->
      Unix.close ready_r; Unix.close release_w;
      ignore (Storage.with_write_lock ~issue_dir (fun () ->
        ignore (Unix.write_substring ready_w "!" 0 1);
        let signal = Bytes.create 1 in
        ignore (Unix.read release_r signal 0 1);
        (* crash: exit while holding the lock, no cleanup *)
        if crash then Unix._exit 3));
      Unix._exit 0
    | pid ->
      Unix.close ready_w; Unix.close release_r;
      let signal = Bytes.create 1 in
      assert (Unix.read ready_r signal 0 1 = 1);
      Unix.close ready_r;
      (pid, release_w)
  in
  let child, release = hold ~issue_dir:".ditz" ~crash:false in
  Unix.putenv "DITZ_LOCK_TIMEOUT" "0.3";
  let ran = ref false in
  (match Storage.with_write_lock (fun () -> ran := true) with
   | Ok () -> failwith "expected the lock to time out while another process holds it"
   | Error (`Msg m) -> assert (contains m "another ditz command"));
  assert (not !ran);
  print_endline "PASS: contended lock times out with a retry hint, body not run";

  (* with a longer timeout it waits for the holder and then runs *)
  Unix.close release;
  Unix.putenv "DITZ_LOCK_TIMEOUT" "10";
  assert (Storage.with_write_lock (fun () -> "after") = Ok "after");
  ignore (Unix.waitpid [] child);
  print_endline "PASS: waits for the holder, then runs";

  (* a holder that dies mid-command cannot leave a stale lock *)
  let crasher, release = hold ~issue_dir:".ditz" ~crash:true in
  Unix.close release;
  Unix.putenv "DITZ_LOCK_TIMEOUT" "5";
  assert (Storage.with_write_lock (fun () -> ()) = Ok ());
  ignore (Unix.waitpid [] crasher);
  print_endline "PASS: a crashed holder releases the lock";

  (* A git hook inherits the marker from its parent ditz process. A nested
     writer in that hook must fail immediately rather than waiting for its
     parent to release the lock after the hook returns. *)
  (match Storage.with_write_lock (fun () -> Storage.with_write_lock (fun () -> ())) with
   | Ok (Error (`Msg m)) -> assert (contains m "reentry")
   | _ -> failwith "nested writer did not fail fast");
  assert (Storage.with_write_lock (fun () -> 9) = Ok 9);
  print_endline "PASS: nested writer fails fast and marker is cleared";

  let custom = Filename.concat dir "custom" in
  Unix.mkdir custom 0o755;
  assert (Storage.with_write_lock ~issue_dir:custom (fun () -> ()) = Ok ());
  assert (Sys.file_exists (Filename.concat custom ".ditz-write.lock"));
  assert (Sys.file_exists ".ditz/.ditz-write.lock");
  print_endline "PASS: configured filesystem directory has its own lock";

  Unix.symlink custom "custom-alias";
  let child, release = hold ~issue_dir:custom ~crash:false in
  Unix.putenv "DITZ_LOCK_TIMEOUT" "0";
  (match Storage.with_write_lock ~issue_dir:"custom-alias" (fun () -> ()) with
   | Error (`Msg m) -> assert (contains m "another ditz command")
   | Ok () -> failwith "symlink alias bypassed the configured directory lock");
  Unix.close release;
  ignore (Unix.waitpid [] child);
  print_endline "PASS: directory aliases converge on one lock";

  (* no tracker at all: nothing to lock, body still runs *)
  Sys.chdir (make_temp_dir "ditz_nolock");
  assert (Storage.with_write_lock (fun () -> 7) = Ok 7);
  print_endline "PASS: no tracker, no lock";
  print_endline "\nAll lock tests passed!"
