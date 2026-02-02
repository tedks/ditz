(** Tests for git integration module. *)

open Ditz

(** Create a temporary directory *)
let make_temp_dir prefix =
  let path = Filename.temp_file prefix "" in
  Sys.remove path;
  Unix.mkdir path 0o755;
  path

(** Remove directory recursively *)
let rm_rf path =
  let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote path)) in
  ()

(** Run a command in a directory *)
let run_in ~cwd cmd =
  let full_cmd = Printf.sprintf "cd %s && %s > /dev/null 2>&1" (Filename.quote cwd) cmd in
  let code = Sys.command full_cmd in
  if code <> 0 then failwith (Printf.sprintf "Command failed: %s" cmd)

(** Initialize a git repo in a directory *)
let init_git_repo dir =
  run_in ~cwd:dir "git init";
  run_in ~cwd:dir "git config user.email 'test@example.com'";
  run_in ~cwd:dir "git config user.name 'Test'";
  run_in ~cwd:dir "echo 'hello' > README.md";
  run_in ~cwd:dir "git add .";
  run_in ~cwd:dir "git commit -m 'Initial commit'"

(** Test helper to run tests in a temp git repo, then clean up *)
let with_temp_git_repo f =
  let old_cwd = Sys.getcwd () in
  let temp_dir = make_temp_dir "ditz_git_test" in
  try
    init_git_repo temp_dir;
    Sys.chdir temp_dir;
    let result = f temp_dir in
    Sys.chdir old_cwd;
    rm_rf temp_dir;
    result
  with e ->
    Sys.chdir old_cwd;
    rm_rf temp_dir;
    raise e

(** Test helper to run tests in a non-git directory *)
let with_temp_non_git_dir f =
  let old_cwd = Sys.getcwd () in
  let temp_dir = make_temp_dir "ditz_non_git_test" in
  try
    Sys.chdir temp_dir;
    let result = f temp_dir in
    Sys.chdir old_cwd;
    rm_rf temp_dir;
    result
  with e ->
    Sys.chdir old_cwd;
    rm_rf temp_dir;
    raise e

let assert_ok = function
  | Ok v -> v
  | Error (`Msg e) -> failwith (Printf.sprintf "Expected Ok, got Error: %s" e)

let assert_error = function
  | Ok _ -> failwith "Expected Error, got Ok"
  | Error _ -> ()

(* ============ Tests ============ *)

let test_is_git_repo () =
  (* In a git repo *)
  with_temp_git_repo (fun _ ->
    assert (Git.is_git_repo ())
  );
  (* Not in a git repo *)
  with_temp_non_git_dir (fun _ ->
    assert (not (Git.is_git_repo ()))
  );
  Printf.printf "PASS: is_git_repo\n"

let test_find_git_root () =
  with_temp_git_repo (fun temp_dir ->
    match Git.find_git_root () with
    | Some root -> assert (root = temp_dir)
    | None -> failwith "Expected to find git root"
  );
  with_temp_non_git_dir (fun _ ->
    match Git.find_git_root () with
    | Some _ -> failwith "Expected no git root"
    | None -> ()
  );
  Printf.printf "PASS: find_git_root\n"

let test_branch_exists () =
  with_temp_git_repo (fun _ ->
    (* master/main should exist *)
    assert (Git.branch_exists "master" || Git.branch_exists "main");
    (* random branch should not exist *)
    assert (not (Git.branch_exists "nonexistent-branch"))
  );
  Printf.printf "PASS: branch_exists\n"

let test_ditz_metadata_exists () =
  with_temp_git_repo (fun _ ->
    (* Before init, should not exist *)
    assert (not (Git.ditz_metadata_exists ()));
    (* Create it *)
    let _ = assert_ok (Git.create_ditz_metadata_branch ~project_name:"test") in
    (* Now should exist *)
    assert (Git.ditz_metadata_exists ())
  );
  Printf.printf "PASS: ditz_metadata_exists\n"

let test_create_ditz_metadata_branch () =
  with_temp_git_repo (fun _ ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"TestProject") in
    assert (Git.ditz_metadata_exists ());
    (* Second create should fail *)
    assert_error (Git.create_ditz_metadata_branch ~project_name:"TestProject")
  );
  Printf.printf "PASS: create_ditz_metadata_branch\n"

let test_read_file_from_branch () =
  with_temp_git_repo (fun _ ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"TestProject") in
    (* Should be able to read project.yaml *)
    let content = assert_ok (Git.read_file_from_branch ".ditz/project.yaml") in
    assert (String.length content > 0);
    assert (String.sub content 0 5 = "name:");
    (* Reading nonexistent file should fail *)
    assert_error (Git.read_file_from_branch ".ditz/nonexistent.yaml")
  );
  Printf.printf "PASS: read_file_from_branch\n"

let test_list_ditz_files () =
  with_temp_git_repo (fun _ ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"TestProject") in
    let files = Git.list_ditz_files () in
    assert (List.exists (fun f -> String.sub (Filename.basename f) 0 7 = "project") files)
  );
  Printf.printf "PASS: list_ditz_files\n"

let test_write_to_branch () =
  with_temp_git_repo (fun _ ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"TestProject") in
    (* Write a new file *)
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-test1.yaml"
      ~content:"id: test1\ntitle: Test Issue\n"
      ~commit_msg:"Add test issue") in
    (* Should be able to read it back *)
    let content = assert_ok (Git.read_file_from_branch ".ditz/issue-test1.yaml") in
    assert (String.sub content 0 3 = "id:");
    (* File should appear in list *)
    let files = Git.list_ditz_files () in
    assert (List.exists (fun f -> Filename.basename f = "issue-test1.yaml") files)
  );
  Printf.printf "PASS: write_to_branch\n"

let test_delete_from_branch () =
  with_temp_git_repo (fun _ ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"TestProject") in
    (* Write a file first *)
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-todelete.yaml"
      ~content:"id: todelete\n"
      ~commit_msg:"Add issue to delete") in
    (* Verify it exists *)
    let _ = assert_ok (Git.read_file_from_branch ".ditz/issue-todelete.yaml") in
    (* Delete it *)
    let () = assert_ok (Git.delete_from_branch
      ~path:".ditz/issue-todelete.yaml"
      ~commit_msg:"Delete issue") in
    (* Should no longer exist *)
    assert_error (Git.read_file_from_branch ".ditz/issue-todelete.yaml")
  );
  Printf.printf "PASS: delete_from_branch\n"

let test_persistent_worktree () =
  with_temp_git_repo (fun temp_dir ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"TestProject") in
    (* Worktree should not exist yet *)
    assert (not (Git.persistent_worktree_valid ()));
    (* Create persistent worktree *)
    let path = assert_ok (Git.create_persistent_worktree ()) in
    assert (path = Filename.concat temp_dir ".ditz-worktree");
    assert (Sys.file_exists path);
    assert (Git.persistent_worktree_valid ());
    (* Second create should succeed (returns existing) *)
    let path2 = assert_ok (Git.create_persistent_worktree ()) in
    assert (path = path2)
  );
  Printf.printf "PASS: persistent_worktree\n"

let test_ephemeral_worktree () =
  (* Test that ephemeral mode works when no persistent worktree exists *)
  with_temp_git_repo (fun temp_dir ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"TestProject") in
    (* Set ephemeral mode *)
    Unix.putenv "DITZ_EPHEMERAL_WORKTREE" "1";
    (* Write should work *)
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-eph.yaml"
      ~content:"id: eph\n"
      ~commit_msg:"Ephemeral test") in
    (* Persistent worktree should NOT have been created *)
    let worktree_path = Filename.concat temp_dir ".ditz-worktree" in
    assert (not (Sys.file_exists worktree_path));
    (* File should still be readable *)
    let _ = assert_ok (Git.read_file_from_branch ".ditz/issue-eph.yaml") in
    (* Clean up env *)
    Unix.putenv "DITZ_EPHEMERAL_WORKTREE" ""
  );
  Printf.printf "PASS: ephemeral_worktree\n"

let test_storage_git_backend () =
  with_temp_git_repo (fun _ ->
    (* Initialize via storage module *)
    let () = assert_ok (Storage.init_project ~name:"StorageTest" ~issue_dir:".ditz") in
    assert (Git.ditz_metadata_exists ());
    assert (Storage.is_git_backend ());
    (* Load project *)
    let project = assert_ok (Storage.load_project ".ditz") in
    assert (project.Types.name = "StorageTest");
    (* Create an issue *)
    let issue = {
      Types.id = "storage-test-1";
      title = "Storage Test Issue";
      desc = "Testing storage module with git backend";
      issue_type = Types.Task;
      component = "StorageTest";
      release = None;
      reporter = "Test <test@example.com>";
      status = Types.Unstarted;
      disposition = None;
      creation_time = "2026-01-30T00:00:00Z";
      references = [];
      log_events = [];
      blocks = [];
      blocked_by = [];
      file_refs = [];
    } in
    let () = assert_ok (Storage.save_issue ".ditz" issue) in
    (* Load it back *)
    let loaded = assert_ok (Storage.find_issue_by_id ".ditz" "storage-test-1") in
    assert (loaded.Types.id = "storage-test-1");
    assert (loaded.Types.title = "Storage Test Issue");
    (* List issues *)
    let issues = Storage.load_issues ".ditz" in
    assert (List.length issues = 1);
    (* Delete issue *)
    let () = assert_ok (Storage.delete_issue ".ditz" "storage-test-1") in
    let issues_after = Storage.load_issues ".ditz" in
    assert (List.length issues_after = 0)
  );
  Printf.printf "PASS: storage_git_backend\n"

let () =
  Printf.printf "Running git integration tests...\n\n";
  test_is_git_repo ();
  test_find_git_root ();
  test_branch_exists ();
  test_ditz_metadata_exists ();
  test_create_ditz_metadata_branch ();
  test_read_file_from_branch ();
  test_list_ditz_files ();
  test_write_to_branch ();
  test_delete_from_branch ();
  test_persistent_worktree ();
  test_ephemeral_worktree ();
  test_storage_git_backend ();
  Printf.printf "\nAll git integration tests passed!\n"
