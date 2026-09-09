(** Tests for ambiguous issue ID prefix handling. *)

open Ditz

let base_issue id =
  {
    Types.id;
    title = "Test issue";
    desc = "";
    issue_type = Types.Task;
    component = "default";
    release = None;
    reporter = "Tester <test@example.com>";
    status = Types.Unstarted;
    disposition = None;
    creation_time = "2026-01-30T00:00:00Z";
    references = [];
    log_events = [];
    blocks = [];
    blocked_by = [];
    file_refs = [];
  }

let save_issue dir issue =
  match Storage.save_issue dir issue with
  | Ok () -> ()
  | Error (`Msg e) -> failwith e

let with_temp_dir f =
  let old_cwd = Sys.getcwd () in
  let path = Filename.temp_file "ditz-test-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  let cleanup () =
    Sys.chdir old_cwd;
    if Sys.file_exists path then begin
      Sys.readdir path
      |> Array.iter (fun name -> Sys.remove (Filename.concat path name));
      Unix.rmdir path
    end
  in
  try
    (* Change to temp dir so we're not in a git repo *)
    Sys.chdir path;
    let result = f path in
    cleanup ();
    result
  with exn ->
    cleanup ();
    raise exn

let () =
  with_temp_dir (fun dir ->
    save_issue dir (base_issue "abc123");
    save_issue dir (base_issue "abc999");

    (match Storage.find_issue_by_id dir "abc" with
     | Ok _ -> failwith "expected ambiguous prefix error"
     | Error _ -> ());

    let issue =
      match Storage.find_issue_by_id dir "abc1" with
      | Ok v -> v
      | Error (`Msg e) -> failwith e
    in
    assert (issue.Types.id = "abc123");

    let issue =
      match Storage.find_issue_by_id dir "abc999" with
      | Ok v -> v
      | Error (`Msg e) -> failwith e
    in
    assert (issue.Types.id = "abc999");

    (* An exact id is never ambiguous, even when it prefixes its siblings. The
       beads import renames "goals-53u.1" to "goals-53u-1", which makes the
       epic's own id a strict prefix of every child's; without exact-match
       precedence the epic cannot be shown, closed, or dropped at all. *)
    save_issue dir (base_issue "epic-1");
    save_issue dir (base_issue "epic-1-a");
    save_issue dir (base_issue "epic-1-b");
    (match Storage.find_issue_by_id dir "epic-1" with
     | Ok v -> assert (v.Types.id = "epic-1")
     | Error (`Msg e) -> failwith ("exact id should win over prefixes: " ^ e));
    (* a genuine prefix that matches several and is not itself an id still errors *)
    (match Storage.find_issue_by_id dir "epic-1-" with
     | Ok _ -> failwith "expected ambiguous error for non-exact prefix"
     | Error _ -> ()))
