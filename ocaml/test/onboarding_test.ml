(** Tests for the clobber-safe AGENTS.md onboarding installer. *)

open Ditz

let make_temp_dir prefix =
  let path = Filename.temp_file prefix "" in
  Sys.remove path; Unix.mkdir path 0o700; path

let read path = Fs_util.read_file path

let is_wrote = function Onboarding.Wrote _ -> true | _ -> false
let is_skipped = function Onboarding.Skipped_present _ -> true | _ -> false
let outcome_name = function
  | Onboarding.Wrote _ -> "Wrote" | Skipped_present _ -> "Skipped"
  | Refused_symlink -> "Refused" | Failed _ -> "Failed"

let () =
  let dir = make_temp_dir "ditz_onboard" in
  at_exit (fun () -> ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir))));
  let agents = Filename.concat dir "AGENTS.md" in

  (* fresh file: writes the block between markers *)
  assert (is_wrote (Onboarding.install ~within:None ~path:agents));
  let c = read agents in
  assert (Onboarding.contains c Onboarding.marker_start);
  assert (Onboarding.contains c Onboarding.marker_end);
  assert (Onboarding.contains c "ditz ready");
  print_endline "PASS: writes block to fresh file";

  (* idempotent: second install is a no-op (markers already present) *)
  assert (is_skipped (Onboarding.install ~within:None ~path:agents));
  let c2 = read agents in
  assert (c = c2);   (* unchanged *)
  print_endline "PASS: idempotent (skips when present)";

  (* existing user content is preserved (appended, never overwritten) *)
  let userfile = Filename.concat dir "EXISTING.md" in
  let oc = open_out userfile in
  output_string oc "# My project\n\nHand-written instructions.\n"; close_out oc;
  assert (is_wrote (Onboarding.install ~within:None ~path:userfile));
  let uc = read userfile in
  assert (Onboarding.contains uc "Hand-written instructions.");   (* preserved *)
  assert (Onboarding.contains uc Onboarding.marker_start);        (* appended *)
  print_endline "PASS: preserves existing content (append, not overwrite)";

  (* symlink: refused, and the link target is left untouched *)
  let target = Filename.concat dir "canonical.md" in
  let oc = open_out target in output_string oc "CANONICAL\n"; close_out oc;
  let link = Filename.concat dir "LINK.md" in
  Unix.symlink target link;
  assert (Onboarding.install ~within:None ~path:link = Onboarding.Refused_symlink);
  assert (read target = "CANONICAL\n");                  (* target untouched *)
  assert ((Unix.lstat link).Unix.st_kind = Unix.S_LNK); (* link still a link *)
  print_endline "PASS: refuses symlink with no repo context";

  (* in-repo symlink target (AGENTS.md -> ./canonical.md): follow it and write
     into the target, since it's inside [within]. The reported destination must
     be the RESOLVED target, not the link path (that's the whole fix). *)
  let real_target = Unix.realpath target in
  (match Onboarding.install ~within:(Some dir) ~path:link with
   | Onboarding.Wrote d -> assert (d = real_target)
   | o -> failwith ("expected Wrote target, got " ^ outcome_name o));
  ignore is_wrote;
  let tc = read target in
  assert (Onboarding.contains tc "CANONICAL");            (* original preserved *)
  assert (Onboarding.contains tc Onboarding.marker_start);(* block written into target *)
  assert ((Unix.lstat link).Unix.st_kind = Unix.S_LNK);  (* link still a link *)
  (* and it's idempotent through the link now, still reporting the target *)
  (match Onboarding.install ~within:(Some dir) ~path:link with
   | Onboarding.Skipped_present d -> assert (d = real_target)
   | o -> failwith ("expected Skipped_present target, got " ^ outcome_name o));
  print_endline "PASS: follows in-repo symlink, writes+reports target";

  (* out-of-repo symlink target (e.g. ~/.claude/CLAUDE.md): refused even with a
     repo context — never write through to a shared global file. *)
  let outside = make_temp_dir "ditz_onboard_outside" in
  at_exit (fun () -> ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote outside))));
  let ext_target = Filename.concat outside "canonical.md" in
  let oc = open_out ext_target in output_string oc "GLOBAL\n"; close_out oc;
  let ext_link = Filename.concat dir "EXTLINK.md" in
  Unix.symlink ext_target ext_link;
  assert (Onboarding.install ~within:(Some dir) ~path:ext_link = Onboarding.Refused_symlink);
  assert (read ext_target = "GLOBAL\n");                  (* outside file untouched *)
  print_endline "PASS: refuses out-of-repo symlink target";

  (* CRITICAL regression: an existing-but-unreadable file must NOT be clobbered
     (treated as empty and replaced). Refuse, leave it byte-for-byte intact. *)
  let unreadable = Filename.concat dir "UNREADABLE.md" in
  let oc = open_out unreadable in output_string oc "PRECIOUS USER CONTENT\n"; close_out oc;
  Unix.chmod unreadable 0o000;
  (* (root can read 000 files; skip the destructive assertion if so) *)
  let readable_as_empty = (try ignore (read unreadable); true with _ -> false) in
  if not readable_as_empty then begin
    (match Onboarding.install ~within:None ~path:unreadable with
     | Onboarding.Failed _ -> () | o -> failwith (Printf.sprintf "expected Failed on unreadable, got %s"
       (outcome_name o)));
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
  (match Onboarding.install ~within:None ~path:asdir with
   | Onboarding.Failed _ -> () | _ -> failwith "expected Failed when path is a directory");
  assert (Sys.is_directory asdir);
  print_endline "PASS: refuses directory path";

  print_endline "\nAll onboarding tests passed!"
