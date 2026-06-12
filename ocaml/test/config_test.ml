(** Tests for identity resolution: config file > DITZ_USER/DITZ_EMAIL > git config. *)

open Ditz

let run cmd =
  if Sys.command cmd <> 0 then failwith ("command failed: " ^ cmd)

let make_temp_dir prefix =
  let path = Filename.temp_file prefix "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let rm_rf path =
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote path)))

let contains haystack needle =
  let hl = String.length haystack and nl = String.length needle in
  let rec go i = i + nl <= hl && (String.sub haystack i nl = needle || go (i + 1)) in
  go 0

let () =
  let original_cwd = Sys.getcwd () in

  (* Isolate from the real environment: empty HOME, no global/system git config.
     putenv "" (not unset) suffices for DITZ_* only because the resolver treats
     blank-after-trim as absent — that behavior is itself under test in case 3. *)
  let home = make_temp_dir "ditz_config_home" in
  Unix.putenv "HOME" home;
  Unix.putenv "GIT_CONFIG_GLOBAL" "/dev/null";
  Unix.putenv "GIT_CONFIG_SYSTEM" "/dev/null";
  Unix.putenv "DITZ_USER" "";
  Unix.putenv "DITZ_EMAIL" "";

  let repo = make_temp_dir "ditz_config_repo" in
  let cleanup () = Sys.chdir original_cwd; rm_rf home; rm_rf repo in
  at_exit cleanup;
  Sys.chdir repo;
  run "git init -q";

  (* 1. Nothing available -> error that says how to fix it *)
  (match Storage.load_config () with
   | Error (`Msg m) ->
     assert (contains m "git config");
     assert (contains m "DITZ_USER")
   | Ok _ -> failwith "expected error with no identity anywhere");
  Printf.printf "PASS: no identity -> error\n";

  (* 2. Git identity alone is enough *)
  run "git config user.name 'Git Name'";
  run "git config user.email git@example.com";
  (match Storage.load_config () with
   | Ok c ->
     assert (c.Types.name = "Git Name");
     assert (c.Types.email = "git@example.com");
     assert (c.Types.issue_dir = ".ditz")
   | Error (`Msg m) -> failwith ("expected git identity, got error: " ^ m));
  Printf.printf "PASS: git config fallback\n";

  (* 3. DITZ_USER/DITZ_EMAIL override git config *)
  Unix.putenv "DITZ_USER" "Env Name";
  Unix.putenv "DITZ_EMAIL" "env@example.com";
  (match Storage.load_config () with
   | Ok c ->
     assert (c.Types.name = "Env Name");
     assert (c.Types.email = "env@example.com")
   | Error (`Msg m) -> failwith ("expected env identity, got error: " ^ m));
  Printf.printf "PASS: env override\n";

  (* 4. Config file wins over everything *)
  let oc = open_out (Filename.concat home ".ditz-config") in
  output_string oc "name: File Name\nemail: file@example.com\nissue_dir: .ditz\n";
  close_out oc;
  (match Storage.load_config () with
   | Ok c ->
     assert (c.Types.name = "File Name");
     assert (c.Types.email = "file@example.com")
   | Error (`Msg m) -> failwith ("expected file identity, got error: " ^ m));
  Printf.printf "PASS: config file precedence\n";

  Printf.printf "\nAll config tests passed!\n"
