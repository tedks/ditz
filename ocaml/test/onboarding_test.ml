(** Tests for the clobber-safe AGENTS.md onboarding installer. *)

open Ditz

let make_temp_dir prefix =
  let path = Filename.temp_file prefix "" in
  Sys.remove path; Unix.mkdir path 0o700; path

let read path = Fs_util.read_file path

let () =
  let dir = make_temp_dir "ditz_onboard" in
  at_exit (fun () -> ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir))));
  let agents = Filename.concat dir "AGENTS.md" in

  (* fresh file: writes the block between markers *)
  assert (Onboarding.install ~path:agents = Onboarding.Wrote);
  let c = read agents in
  assert (Onboarding.contains c Onboarding.marker_start);
  assert (Onboarding.contains c Onboarding.marker_end);
  assert (Onboarding.contains c "ditz ready");
  print_endline "PASS: writes block to fresh file";

  (* idempotent: second install is a no-op (markers already present) *)
  assert (Onboarding.install ~path:agents = Onboarding.Skipped_present);
  let c2 = read agents in
  assert (c = c2);   (* unchanged *)
  print_endline "PASS: idempotent (skips when present)";

  (* existing user content is preserved (appended, never overwritten) *)
  let userfile = Filename.concat dir "EXISTING.md" in
  let oc = open_out userfile in
  output_string oc "# My project\n\nHand-written instructions.\n"; close_out oc;
  assert (Onboarding.install ~path:userfile = Onboarding.Wrote);
  let uc = read userfile in
  assert (Onboarding.contains uc "Hand-written instructions.");   (* preserved *)
  assert (Onboarding.contains uc Onboarding.marker_start);        (* appended *)
  print_endline "PASS: preserves existing content (append, not overwrite)";

  (* symlink: refused, and the link target is left untouched *)
  let target = Filename.concat dir "canonical.md" in
  let oc = open_out target in output_string oc "CANONICAL\n"; close_out oc;
  let link = Filename.concat dir "LINK.md" in
  Unix.symlink target link;
  assert (Onboarding.install ~path:link = Onboarding.Refused_symlink);
  assert (read target = "CANONICAL\n");                  (* target untouched *)
  assert ((Unix.lstat link).Unix.st_kind = Unix.S_LNK); (* link still a link *)
  print_endline "PASS: refuses symlink, leaves target intact";

  (* CRITICAL regression: an existing-but-unreadable file must NOT be clobbered
     (treated as empty and replaced). Refuse, leave it byte-for-byte intact. *)
  let unreadable = Filename.concat dir "UNREADABLE.md" in
  let oc = open_out unreadable in output_string oc "PRECIOUS USER CONTENT\n"; close_out oc;
  Unix.chmod unreadable 0o000;
  (* (root can read 000 files; skip the destructive assertion if so) *)
  let readable_as_empty = (try ignore (read unreadable); true with _ -> false) in
  if not readable_as_empty then begin
    (match Onboarding.install ~path:unreadable with
     | Onboarding.Failed _ -> () | o -> failwith (Printf.sprintf "expected Failed on unreadable, got %s"
       (match o with Wrote -> "Wrote" | Skipped_present -> "Skipped" | Refused_symlink -> "Refused" | Failed _ -> "Failed")));
    Unix.chmod unreadable 0o600;
    assert (read unreadable = "PRECIOUS USER CONTENT\n");   (* untouched *)
    print_endline "PASS: refuses unreadable file, content intact"
  end else begin
    Unix.chmod unreadable 0o600;
    print_endline "SKIP: unreadable-file test (running as root, 000 still readable)"
  end;

  (* a directory at the path is refused, not crashed *)
  let asdir = Filename.concat dir "ASDIR.md" in
  Unix.mkdir asdir 0o755;
  (match Onboarding.install ~path:asdir with
   | Onboarding.Failed _ -> () | _ -> failwith "expected Failed when path is a directory");
  assert (Sys.is_directory asdir);
  print_endline "PASS: refuses directory path";

  print_endline "\nAll onboarding tests passed!"
