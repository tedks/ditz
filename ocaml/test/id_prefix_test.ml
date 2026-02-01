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
  let path = Filename.temp_file "ditz-test-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  let cleanup () =
    if Sys.file_exists path then begin
      Sys.readdir path
      |> Array.iter (fun name -> Sys.remove (Filename.concat path name));
      Unix.rmdir path
    end
  in
  try
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
    assert (issue.Types.id = "abc999"))
