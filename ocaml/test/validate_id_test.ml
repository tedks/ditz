(** Tests for invalid issue ID rejection. *)

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

let expect_error = function
  | Ok _ -> failwith "expected error"
  | Error _ -> ()

let () =
  with_temp_dir (fun dir ->
    let bad_issue = base_issue "bad/../id" in
    expect_error (Storage.save_issue dir bad_issue);
    expect_error (Storage.delete_issue dir "bad/../id");

    let bad_issue = base_issue "bad.id" in
    expect_error (Storage.save_issue dir bad_issue);
    expect_error (Storage.delete_issue dir "bad.id");

    let good_issue = base_issue "Abc123" in
    (match Storage.save_issue dir good_issue with
     | Ok () -> ()
     | Error (`Msg e) -> failwith e);
    (match Storage.delete_issue dir "Abc123" with
     | Ok () -> ()
     | Error (`Msg e) -> failwith e))
