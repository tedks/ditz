(** Tests for the shared atomic/safe file I/O primitives. *)

open Ditz

let make_temp_dir prefix =
  let path = Filename.temp_file prefix "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let () =
  let dir = make_temp_dir "ditz_fs_util" in
  at_exit (fun () ->
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir))));

  (* Round trip *)
  let path = Filename.concat dir "a.yaml" in
  (match Fs_util.write_file_atomic ~path ~content:"hello: world\n" with
   | Ok () -> ()
   | Error (`Msg e) -> failwith e);
  assert (Fs_util.read_file path = "hello: world\n");
  Printf.printf "PASS: write/read round trip\n";

  (* Overwrite replaces content fully *)
  (match Fs_util.write_file_atomic ~path ~content:"x: 1\n" with
   | Ok () -> () | Error (`Msg e) -> failwith e);
  assert (Fs_util.read_file path = "x: 1\n");
  Printf.printf "PASS: overwrite\n";

  (* No temp file droppings on the success path *)
  assert (Array.to_list (Sys.readdir dir) = ["a.yaml"]);
  Printf.printf "PASS: no temp droppings\n";

  (* Symlink at the destination is replaced, not followed: the victim file
     the symlink points at must remain untouched *)
  let victim = Filename.concat dir "victim.txt" in
  (match Fs_util.write_file_atomic ~path:victim ~content:"precious\n" with
   | Ok () -> () | Error (`Msg e) -> failwith e);
  let link = Filename.concat dir "link.yaml" in
  Unix.symlink victim link;
  (match Fs_util.write_file_atomic ~path:link ~content:"attacker\n" with
   | Ok () -> () | Error (`Msg e) -> failwith e);
  assert (Fs_util.read_file victim = "precious\n");
  assert (Fs_util.read_file link = "attacker\n");
  assert ((Unix.lstat link).Unix.st_kind = Unix.S_REG);
  Printf.printf "PASS: symlink not followed\n";

  (* Missing directory -> Error, not exception *)
  (match Fs_util.write_file_atomic
           ~path:(Filename.concat dir "no/such/dir/f.yaml") ~content:"x" with
   | Error (`Msg _) -> ()
   | Ok () -> failwith "expected error for missing directory");
  Printf.printf "PASS: missing dir errors cleanly\n";

  (* read_file on a missing path raises Sys_error (callers catch/avoid) *)
  (match Fs_util.read_file (Filename.concat dir "absent.yaml") with
   | exception Sys_error _ -> ()
   | _ -> failwith "expected Sys_error for missing file");
  Printf.printf "PASS: missing read raises Sys_error\n";

  Printf.printf "\nAll fs_util tests passed!\n"
