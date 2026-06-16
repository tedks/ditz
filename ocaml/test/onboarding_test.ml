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

  print_endline "\nAll onboarding tests passed!"
