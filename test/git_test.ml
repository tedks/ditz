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

let contains haystack needle =
  let hl = String.length haystack and nl = String.length needle in
  let rec go i = i + nl <= hl && (String.sub haystack i nl = needle || go (i + 1)) in
  go 0

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

(* A write commits exactly its own file. Anything else staged in the shared
   worktree (a failed write's leftovers, another process's `git add`) must stay
   out of the commit -- it used to be swept in under the unrelated commit's
   message, which is how stray test issues reached a real tracker. *)
let test_write_commits_only_its_path () =
  with_temp_git_repo (fun _ ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"OwnPath") in
    let () = assert_ok (Git.write_to_branch ~path:".ditz/issue-first.yaml"
                          ~content:"id: first\n" ~commit_msg:"first") in
    let wt = assert_ok (Git.with_worktree (fun wt -> Ok wt)) in
    (* stage a stray file in the worktree, as a failed write would leave it *)
    let stray = Filename.concat wt ".ditz/issue-stray.yaml" in
    let () = assert_ok (Fs_util.write_file_atomic ~path:stray ~content:"id: stray\n") in
    run_in ~cwd:wt "git add .ditz/issue-stray.yaml";
    let () = assert_ok (Git.write_to_branch ~path:".ditz/issue-second.yaml"
                          ~content:"id: second\n" ~commit_msg:"second") in
    let head_files = assert_ok (Git.git ["show"; "--name-only"; "--format="; "ditz-metadata"]) in
    assert (String.trim head_files = ".ditz/issue-second.yaml");
    assert_error (Git.read_file_from_branch ".ditz/issue-stray.yaml");
    (* ...and the stray is left exactly as it was: still staged, not dropped *)
    let staged () = assert_ok (Git.git ~cwd:wt ["diff"; "--cached"; "--name-only"]) in
    assert (String.trim (staged ()) = ".ditz/issue-stray.yaml");
    (* rewriting an unchanged file is a no-op even with the stray still staged *)
    let before = assert_ok (Git.git ["rev-parse"; "ditz-metadata"]) in
    let () = assert_ok (Git.write_to_branch ~path:".ditz/issue-second.yaml"
                          ~content:"id: second\n" ~commit_msg:"again") in
    assert (assert_ok (Git.git ["rev-parse"; "ditz-metadata"]) = before);
    (* deletes are scoped the same way *)
    let () = assert_ok (Git.delete_from_branch ~path:".ditz/issue-first.yaml"
                          ~commit_msg:"delete first") in
    let del_files = assert_ok (Git.git ["show"; "--name-only"; "--format="; "ditz-metadata"]) in
    assert (String.trim del_files = ".ditz/issue-first.yaml");
    assert_error (Git.read_file_from_branch ".ditz/issue-stray.yaml")
  );
  Printf.printf "PASS: write_commits_only_its_path\n"

(* A write whose commit fails is rolled back: nothing staged, the worktree
   file as it was, the branch untouched. With scoped commits a leftover would
   otherwise stay staged forever and block every later merge (sync). A
   failing pre-commit hook stands in for index.lock / commit failures. *)
let test_failed_write_rolls_back () =
  with_temp_git_repo (fun dir ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"Rollback") in
    let () = assert_ok (Git.write_to_branch ~path:".ditz/issue-a.yaml"
                          ~content:"id: a\ntitle: before\n" ~commit_msg:"a") in
    let wt = assert_ok (Git.with_worktree (fun wt -> Ok wt)) in
    let hooks = Filename.concat dir "failing-hooks" in
    Unix.mkdir hooks 0o755;
    let hook = Filename.concat hooks "pre-commit" in
    let oc = open_out hook in output_string oc "#!/bin/sh\nexit 1\n"; close_out oc;
    Unix.chmod hook 0o755;
    run_in ~cwd:dir (Printf.sprintf "git config core.hooksPath %s" (Filename.quote hooks));
    let head () = assert_ok (Git.git ["rev-parse"; "ditz-metadata"]) in
    let before = head () in
    let index_clean () = Result.is_ok (Git.git ~cwd:wt ["diff"; "--cached"; "--quiet"]) in
    (* new file: removed again *)
    assert_error (Git.write_to_branch ~path:".ditz/issue-b.yaml" ~content:"id: b\n" ~commit_msg:"b");
    assert (index_clean ());
    assert (not (Sys.file_exists (Filename.concat wt ".ditz/issue-b.yaml")));
    (* modified file: previous content restored *)
    assert_error (Git.write_to_branch ~path:".ditz/issue-a.yaml"
                    ~content:"id: a\ntitle: after\n" ~commit_msg:"a2");
    assert (index_clean ());
    assert (Fs_util.read_file (Filename.concat wt ".ditz/issue-a.yaml") = "id: a\ntitle: before\n");
    (* delete: file restored *)
    assert_error (Git.delete_from_branch ~path:".ditz/issue-a.yaml" ~commit_msg:"rm a");
    assert (index_clean ());
    assert (Sys.file_exists (Filename.concat wt ".ditz/issue-a.yaml"));
    assert (head () = before);
    (* a target with a staged hand edit AND a further unstaged one: both come
       back exactly -- the staged version in the index, the newer one on disk *)
    let a = Filename.concat wt ".ditz/issue-a.yaml" in
    let put c = assert_ok (Fs_util.write_file_atomic ~path:a ~content:c) in
    put "id: a\ntitle: staged\n";
    run_in ~cwd:wt "git add -- .ditz/issue-a.yaml";
    put "id: a\ntitle: unstaged\n";
    assert_error (Git.write_to_branch ~path:".ditz/issue-a.yaml"
                    ~content:"id: a\ntitle: ours\n" ~commit_msg:"a3");
    assert (assert_ok (Git.git ~cwd:wt ["show"; ":.ditz/issue-a.yaml"]) = "id: a\ntitle: staged");
    assert (Fs_util.read_file a = "id: a\ntitle: unstaged\n");
    run_in ~cwd:wt "git checkout HEAD -- .ditz/issue-a.yaml";
    (* an undo that cannot complete is reported, not swallowed: the hook makes
       the directory read-only before failing, so the new file can't be removed *)
    let ro_hook = Filename.concat hooks "pre-commit" in
    let oc = open_out ro_hook in
    output_string oc "#!/bin/sh\nchmod a-w .ditz\nexit 1\n"; close_out oc;
    (match Git.write_to_branch ~path:".ditz/issue-c.yaml" ~content:"id: c\n" ~commit_msg:"c" with
     | Ok () -> failwith "expected the commit to fail"
     | Error (`Msg m) ->
       Unix.chmod (Filename.concat wt ".ditz") 0o755;
       if Unix.getuid () <> 0 then assert (contains m "incomplete"));
    (try Sys.remove (Filename.concat wt ".ditz/issue-c.yaml") with Sys_error _ -> ());
    let oc = open_out ro_hook in output_string oc "#!/bin/sh\nexit 1\n"; close_out oc;
    (* an existing file that can't be read is refused BEFORE anything changes *)
    if Unix.getuid () <> 0 then begin
      Unix.chmod a 0o000;
      (match Git.write_to_branch ~path:".ditz/issue-a.yaml" ~content:"id: a\n" ~commit_msg:"a4" with
       | Ok () -> failwith "expected a refusal for an unreadable target"
       | Error (`Msg m) -> assert (contains m "cannot read"));
      Unix.chmod a 0o644;
      assert (Fs_util.read_file a = "id: a\ntitle: before\n")
    end;
    (* and once commits work again, writes go through *)
    run_in ~cwd:dir "git config --unset core.hooksPath";
    let () = assert_ok (Git.write_to_branch ~path:".ditz/issue-b.yaml" ~content:"id: b\n" ~commit_msg:"b") in
    assert (head () <> before)
  );
  Printf.printf "PASS: failed_write_rolls_back\n"

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

let test_find_common_root () =
  with_temp_git_repo (fun temp_dir ->
    match Git.find_common_root () with
    | Some root -> assert (root = temp_dir)
    | None -> failwith "Expected to find common root"
  );
  with_temp_non_git_dir (fun _ ->
    match Git.find_common_root () with
    | Some _ -> failwith "Expected no common root"
    | None -> ()
  );
  Printf.printf "PASS: find_common_root\n"

let test_find_common_root_from_subdirectory () =
  with_temp_git_repo (fun temp_dir ->
    let subdir = Filename.concat temp_dir "subdir" in
    Unix.mkdir subdir 0o755;
    Sys.chdir subdir;
    match Git.find_common_root () with
    | Some root -> assert (root = temp_dir)
    | None -> failwith "Expected to find common root from subdirectory"
  );
  Printf.printf "PASS: find_common_root_from_subdirectory\n"

let test_find_existing_ditz_worktree () =
  with_temp_git_repo (fun _ ->
    (* Before creating branch/worktree, should be None *)
    assert (Git.find_existing_ditz_worktree () = None);
    (* Create the branch *)
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"TestProject") in
    (* Still None — branch exists but no worktree yet *)
    assert (Git.find_existing_ditz_worktree () = None);
    (* Create persistent worktree *)
    let path = assert_ok (Git.create_persistent_worktree ()) in
    (* Now it should find the worktree *)
    (match Git.find_existing_ditz_worktree () with
     | Some found -> assert (found = path)
     | None -> failwith "Expected to find ditz worktree after creation")
  );
  Printf.printf "PASS: find_existing_ditz_worktree\n"

let test_persistent_worktree_from_external_worktree () =
  with_temp_git_repo (fun temp_dir ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"TestProject") in
    (* Create a separate worktree simulating an external feature branch *)
    let external_wt = temp_dir ^ "-external" in
    let branch =
      match Git.git ["branch"; "--show-current"] with
      | Ok b -> String.trim b
      | Error (`Msg e) -> failwith e
    in
    let _ = assert_ok (Git.git ["worktree"; "add"; "-b"; "feature-test"; external_wt; branch]) in
    (* chdir into the external worktree *)
    Sys.chdir external_wt;
    (* persistent_worktree_path should point to <common-root>/.ditz-worktree, NOT external_wt/.ditz-worktree *)
    let expected = Filename.concat temp_dir ".ditz-worktree" in
    (match Git.persistent_worktree_path () with
     | Some path -> assert (path = expected)
     | None -> failwith "Expected persistent worktree path from external worktree");
    (* Clean up the external worktree *)
    Sys.chdir temp_dir;
    let _ = Git.git ["worktree"; "remove"; "--force"; external_wt] in
    ()
  );
  Printf.printf "PASS: persistent_worktree_from_external_worktree\n"

let test_persistent_worktree_from_inside_ditz_worktree () =
  with_temp_git_repo (fun temp_dir ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"TestProject") in
    (* Create the persistent worktree *)
    let wt_path = assert_ok (Git.create_persistent_worktree ()) in
    let expected = Filename.concat temp_dir ".ditz-worktree" in
    assert (wt_path = expected);
    (* chdir INTO the .ditz-worktree *)
    Sys.chdir wt_path;
    (* persistent_worktree_path should return the SAME path, not a nested one *)
    (match Git.persistent_worktree_path () with
     | Some path ->
       assert (path = expected)
     | None -> failwith "Expected persistent worktree path from inside ditz worktree");
    Sys.chdir temp_dir
  );
  Printf.printf "PASS: persistent_worktree_from_inside_ditz_worktree\n"

let test_write_from_external_worktree () =
  with_temp_git_repo (fun temp_dir ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"TestProject") in
    (* Create an external worktree *)
    let external_wt = temp_dir ^ "-external2" in
    let branch =
      match Git.git ["branch"; "--show-current"] with
      | Ok b -> String.trim b
      | Error (`Msg e) -> failwith e
    in
    let _ = assert_ok (Git.git ["worktree"; "add"; "-b"; "feature-write"; external_wt; branch]) in
    (* chdir into external worktree *)
    Sys.chdir external_wt;
    (* Write an issue — should succeed and go to the common root's .ditz-worktree *)
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-from-external.yaml"
      ~content:"id: from-external\ntitle: Written from external worktree\n"
      ~commit_msg:"Add issue from external worktree") in
    (* Read it back *)
    let content = assert_ok (Git.read_file_from_branch ".ditz/issue-from-external.yaml") in
    assert (String.sub content 0 3 = "id:");
    (* Clean up *)
    Sys.chdir temp_dir;
    let _ = Git.git ["worktree"; "remove"; "--force"; external_wt] in
    ()
  );
  Printf.printf "PASS: write_from_external_worktree\n"

(** Build a bare-at-root layout like ~/Projects/<proj>: the project directory
    IS the bare git dir, with worktrees nested inside it. *)
let make_bare_at_root_layout prefix =
  let seed = make_temp_dir (prefix ^ "_seed") in
  init_git_repo seed;
  let bare = make_temp_dir (prefix ^ "_bare") in
  rm_rf bare;
  run_in ~cwd:"/tmp" (Printf.sprintf "git clone --bare %s %s"
    (Filename.quote seed) (Filename.quote bare));
  run_in ~cwd:bare "git config user.email 'test@example.com'";
  run_in ~cwd:bare "git config user.name 'Test'";
  let main = Filename.concat bare "main" in
  run_in ~cwd:bare (Printf.sprintf "git worktree add %s" (Filename.quote main));
  rm_rf seed;
  (bare, main)

let test_bare_at_root_layout () =
  let (bare, main) = make_bare_at_root_layout "ditz_bare" in
  let old_cwd = Sys.getcwd () in
  (try
    Sys.chdir main;
    (* The container must be the bare dir itself, never its parent — the
       parent is shared with unrelated sibling projects *)
    (match Git.find_common_root () with
     | Some root -> assert (root = bare)
     | None -> failwith "Expected common root in bare-at-root layout");
    (match Git.persistent_worktree_path () with
     | Some p -> assert (p = Filename.concat bare ".ditz-worktree")
     | None -> failwith "Expected persistent worktree path");
    (* init from the bare root itself must not crash *)
    Sys.chdir bare;
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"bareproj") in
    assert (Git.ditz_metadata_exists ());
    (* end-to-end write from the nested worktree, then list *)
    Sys.chdir main;
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-bare1.yaml"
      ~content:"id: bare1\ntitle: bare layout\n"
      ~commit_msg:"test bare layout") in
    let files = Git.list_ditz_files () in
    assert (List.exists (fun f -> Filename.basename f = "issue-bare1.yaml") files);
    Sys.chdir old_cwd;
    rm_rf bare
  with e -> Sys.chdir old_cwd; rm_rf bare; raise e);
  Printf.printf "PASS: bare_at_root_layout\n"

let test_foreign_worktree_rejected () =
  (* Repo A's ditz worktree sitting at repo B's canonical path must NOT be
     accepted by B — accepting it would send B's issue writes into A's
     tracker (reported success, wrong repository). *)
  let a = make_temp_dir "ditz_owner_a" in
  let b = make_temp_dir "ditz_owner_b" in
  let old_cwd = Sys.getcwd () in
  (try
    init_git_repo a;
    init_git_repo b;
    Sys.chdir a;
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"A") in
    let foreign = Filename.concat b ".ditz-worktree" in
    run_in ~cwd:a (Printf.sprintf "git worktree add %s ditz-metadata"
      (Filename.quote foreign));
    Sys.chdir b;
    assert (not (Git.persistent_worktree_valid ()));
    (* Creation must refuse loudly rather than adopt the foreign worktree *)
    assert_error (Git.create_persistent_worktree ());
    Sys.chdir old_cwd;
    rm_rf a; rm_rf b
  with e -> Sys.chdir old_cwd; rm_rf a; rm_rf b; raise e);
  Printf.printf "PASS: foreign_worktree_rejected\n"

let test_list_from_subdirectory () =
  with_temp_git_repo (fun temp_dir ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"T") in
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-sub1.yaml"
      ~content:"id: sub1\ntitle: from subdir\n"
      ~commit_msg:"test subdir") in
    let sub = Filename.concat temp_dir "src" in
    Unix.mkdir sub 0o755;
    Sys.chdir sub;
    (* The old pathspec form resolved ".ditz/" relative to the cwd and
       silently returned [] from any subdirectory *)
    let files = Git.list_ditz_files () in
    assert (List.exists (fun f -> Filename.basename f = "issue-sub1.yaml") files);
    Sys.chdir temp_dir
  );
  Printf.printf "PASS: list_from_subdirectory\n"

let test_stale_worktree_self_heal () =
  with_temp_git_repo (fun temp_dir ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"T") in
    let path = assert_ok (Git.create_persistent_worktree ()) in
    (* Simulate manual deletion: the directory goes away but git's worktree
       registration survives, which used to wedge every later write on
       "missing but already registered worktree" *)
    rm_rf path;
    assert (Git.find_existing_ditz_worktree () = None);
    let path2 = assert_ok (Git.create_persistent_worktree ()) in
    assert (path2 = Filename.concat temp_dir ".ditz-worktree")
  );
  Printf.printf "PASS: stale_worktree_self_heal\n"

let test_self_heal_spares_other_worktrees () =
  with_temp_git_repo (fun temp_dir ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"T") in
    let ditz_wt = assert_ok (Git.create_persistent_worktree ()) in
    (* A user worktree whose directory has gone missing (e.g. mv'd away):
       prunable in porcelain but REPAIRABLE — the self-heal must not take it *)
    let user_wt = Filename.concat temp_dir "user-feature" in
    run_in ~cwd:temp_dir
      (Printf.sprintf "git worktree add -b user-feature %s" (Filename.quote user_wt));
    rm_rf user_wt;
    rm_rf ditz_wt;
    assert (Git.find_existing_ditz_worktree () = None);
    (match Git.git ["worktree"; "list"; "--porcelain"] with
     | Ok out ->
       (* ditz's stale registration healed; the user's survived *)
       assert (not (contains out ".ditz-worktree"));
       assert (contains out "user-feature")
     | Error (`Msg e) -> failwith e)
  );
  Printf.printf "PASS: self_heal_spares_other_worktrees\n"

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

let test_write_does_not_follow_symlink () =
  with_temp_git_repo (fun temp_dir ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"T") in
    let wt = assert_ok (Git.create_persistent_worktree ()) in
    (* Plant a symlink where the issue file would be written, pointing at a
       file outside the tracker. The write must replace the link, never
       follow it. *)
    let victim = Filename.concat temp_dir "victim.txt" in
    let oc = open_out victim in
    output_string oc "precious\n";
    close_out oc;
    let link_target = Filename.concat (Filename.concat wt ".ditz") "issue-evil1.yaml" in
    Unix.symlink victim link_target;
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-evil1.yaml"
      ~content:"id: evil1\ntitle: symlink test\n"
      ~commit_msg:"symlink test") in
    let ic = open_in victim in
    let line = input_line ic in
    close_in ic;
    assert (line = "precious");
    assert ((Unix.lstat link_target).Unix.st_kind = Unix.S_REG)
  );
  Printf.printf "PASS: write_does_not_follow_symlink\n"

(** Two clones of a shared origin, for sync divergence tests.
    Returns (origin_bare, clone1, clone2); caller cleans all three. *)
let make_cloned_pair prefix =
  let seed = make_temp_dir (prefix ^ "_seed") in
  init_git_repo seed;
  let origin = make_temp_dir (prefix ^ "_origin") in
  rm_rf origin;
  run_in ~cwd:"/tmp" (Printf.sprintf "git clone --bare %s %s"
    (Filename.quote seed) (Filename.quote origin));
  let clone n =
    let c = make_temp_dir (prefix ^ n) in
    rm_rf c;
    run_in ~cwd:"/tmp" (Printf.sprintf "git clone %s %s"
      (Filename.quote origin) (Filename.quote c));
    run_in ~cwd:c "git config user.email 'test@example.com'";
    run_in ~cwd:c "git config user.name 'Test'";
    c
  in
  let c1 = clone "_c1" and c2 = clone "_c2" in
  rm_rf seed;
  (origin, c1, c2)

(* Issue fixture in the tool's serialized format; events/title/status differ
   per call so the clones can diverge meaningfully. *)
let sync_issue_yaml ~id ~title ~status ~events =
  let event_block =
    events
    |> List.map (fun (time, what, comment) ->
        Printf.sprintf "- time: %s\n  who: W <w@example.com>\n  what: %s\n  comment: %s"
          time what comment)
    |> String.concat "\n"
  in
  Printf.sprintf
    {|id: %s
title: %s
desc: ""
type:
  Task: []
component: default
release:
reporter: W <w@example.com>
status:
  %s: []
disposition:
creation_time: 2026-06-01T00:00:00-00:00
references: []
log_events:
%s
|}
    id title status event_block

let test_sync_auto_resolves_divergence () =
  let origin, c1, c2 = make_cloned_pair "ditz_sync" in
  let old_cwd = Sys.getcwd () in
  let cleanup () = Sys.chdir old_cwd; rm_rf origin; rm_rf c1; rm_rf c2 in
  (try
    let created = [ ("2026-06-01T00:00:00-00:00", "created", "\"\"") ] in
    (* clone1 creates the tracker and the shared base issue, pushes *)
    Sys.chdir c1;
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"S") in
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-sync1.yaml"
      ~content:(sync_issue_yaml ~id:"sync1" ~title:"Shared" ~status:"Unstarted" ~events:created)
      ~commit_msg:"base") in
    let () = assert_ok (Git.sync ()) in
    (* clone2 onboards (local branch from remote -- onboarding gap workaround),
       then diverges: status change with a NEWER event *)
    Sys.chdir c2;
    run_in ~cwd:c2 "git fetch origin";
    (* local branch auto-created by ensure_local_branch now; no workaround *)
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-sync1.yaml"
      ~content:(sync_issue_yaml ~id:"sync1" ~title:"Shared" ~status:"In_progress"
        ~events:(created @ [ ("2026-06-03T00:00:00-00:00", "started", "\"\"") ]))
      ~commit_msg:"start on clone2") in
    (* clone1 diverges too: adds an OLDER comment event, pushes first *)
    Sys.chdir c1;
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-sync1.yaml"
      ~content:(sync_issue_yaml ~id:"sync1" ~title:"Shared" ~status:"Unstarted"
        ~events:(created @ [ ("2026-06-02T00:00:00-00:00", "commented", "from c1") ]))
      ~commit_msg:"comment on clone1") in
    let () = assert_ok (Git.sync ()) in
    (* clone2 syncs: conflict on issue-sync1.yaml must auto-resolve *)
    Sys.chdir c2;
    let () = assert_ok (Git.sync ()) in
    let merged = assert_ok (Git.read_file_from_branch ".ditz/issue-sync1.yaml") in
    assert (contains merged "from c1");          (* clone1's comment survived *)
    assert (contains merged "started");          (* clone2's event survived *)
    (* newer status won (LWW); merge re-serializes in scalar form (7.0).
       The fixtures are still written in legacy variant-map form above, so this
       also exercises legacy-read -> scalar-write through the sync path. *)
    assert (contains merged "in_progress");
    assert (not (contains merged "In_progress"));
    (* and clone1 can pull the resolution cleanly *)
    Sys.chdir c1;
    let () = assert_ok (Git.sync ()) in
    let merged1 = assert_ok (Git.read_file_from_branch ".ditz/issue-sync1.yaml") in
    assert (contains merged1 "in_progress");
    cleanup ()
  with e -> cleanup (); raise e);
  Printf.printf "PASS: sync_auto_resolves_divergence\n"

(* A staged leftover in the metadata worktree blocks git merge. sync must say
   which files and how to clear them -- not report a merge that never started
   as "still mid-merge" -- and must not block when there is nothing to merge. *)
let test_sync_names_staged_leftovers () =
  let origin, c1, c2 = make_cloned_pair "ditz_syncstaged" in
  let old_cwd = Sys.getcwd () in
  let cleanup () = Sys.chdir old_cwd; rm_rf origin; rm_rf c1; rm_rf c2 in
  let write id = assert_ok (Git.write_to_branch ~path:(Printf.sprintf ".ditz/issue-%s.yaml" id)
                              ~content:(Printf.sprintf "id: %s\n" id) ~commit_msg:id) in
  (try
    Sys.chdir c1;
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"St") in
    write "s1";
    let () = assert_ok (Git.sync ()) in
    Sys.chdir c2;
    let () = assert_ok (Git.sync ()) in
    let wt = assert_ok (Git.with_worktree (fun wt -> Ok wt)) in
    let () = assert_ok (Fs_util.write_file_atomic
                          ~path:(Filename.concat wt ".ditz/issue-stray.yaml") ~content:"id: stray\n") in
    run_in ~cwd:wt "git add -- .ditz/issue-stray.yaml";
    (* nothing new on origin: the leftover does not block sync *)
    let () = assert_ok (Git.sync ()) in
    (* origin moves ahead: a fast-forward keeps the unrelated leftover staged *)
    Sys.chdir c1;
    write "s2";
    let () = assert_ok (Git.sync ()) in
    Sys.chdir c2;
    let () = assert_ok (Git.sync ()) in
    ignore (assert_ok (Git.read_file_from_branch ".ditz/issue-s2.yaml"));
    assert (String.trim (assert_ok (Git.git ~cwd:wt ["diff"; "--cached"; "--name-only"]))
            = ".ditz/issue-stray.yaml");
    (* both sides move: a real merge is needed, and the leftover is named *)
    write "local";
    Sys.chdir c1;
    write "s3";
    let () = assert_ok (Git.sync ()) in
    Sys.chdir c2;
    (match Git.sync () with
     | Ok () -> failwith "expected sync to refuse with a staged leftover"
     | Error (`Msg m) ->
       assert (contains m "staged changes");
       assert (contains m "issue-stray.yaml");
       assert (not (contains m "mid-merge")));
    (* following the advice unblocks it *)
    run_in ~cwd:wt "git restore --staged -- .ditz/issue-stray.yaml";
    Sys.remove (Filename.concat wt ".ditz/issue-stray.yaml");
    let () = assert_ok (Git.sync ()) in
    ignore (assert_ok (Git.read_file_from_branch ".ditz/issue-s3.yaml"));
    cleanup ()
  with e -> cleanup (); raise e);
  Printf.printf "PASS: sync_names_staged_leftovers\n"

(* A repo whose origin has no remote.origin.fetch refspec (bare-at-root
   layouts built with `git init --bare` + `remote add`) must still PULL on
   sync. `git fetch origin ditz-metadata` only writes FETCH_HEAD there, so the
   merge used a stale origin/ditz-metadata and sync never brought anything in
   while reporting success. And with no origin at all, a pull is an error, not
   a silent no-op. *)
let test_sync_pulls_without_fetch_refspec () =
  let origin, c1, c2 = make_cloned_pair "ditz_norefspec" in
  let old_cwd = Sys.getcwd () in
  let cleanup () = Sys.chdir old_cwd; rm_rf origin; rm_rf c1; rm_rf c2 in
  let write id = assert_ok (Git.write_to_branch ~path:(Printf.sprintf ".ditz/issue-%s.yaml" id)
                              ~content:(Printf.sprintf "id: %s\n" id) ~commit_msg:id) in
  (try
    Sys.chdir c1;
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"N") in
    write "n1";
    let () = assert_ok (Git.sync ()) in
    Sys.chdir c2;
    let () = assert_ok (Git.sync ()) in
    run_in ~cwd:c2 "git config --unset-all remote.origin.fetch";
    Sys.chdir c1;
    write "n2";
    let () = assert_ok (Git.sync ()) in
    Sys.chdir c2;
    let () = assert_ok (Git.sync ()) in
    ignore (assert_ok (Git.read_file_from_branch ".ditz/issue-n2.yaml"));
    cleanup ()
  with e -> cleanup (); raise e);
  with_temp_git_repo (fun _ ->
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"NoOrigin") in
    assert_error (Git.fetch ()));
  Printf.printf "PASS: sync_pulls_without_fetch_refspec\n"

(* sync says what it did, and sync_state says where the clone stands, from
   local refs only. *)
let test_sync_reports_and_state () =
  let origin, c1, c2 = make_cloned_pair "ditz_syncrep" in
  let old_cwd = Sys.getcwd () in
  let cleanup () = Sys.chdir old_cwd; rm_rf origin; rm_rf c1; rm_rf c2 in
  let state () = assert_ok (Git.sync_state ()) in
  let tracking a b = match state () with
    | Git.Tracking { ahead; behind } -> ahead = a && behind = b
    | Git.No_remote_branch -> false
  in
  let write id = assert_ok (Git.write_to_branch ~path:(Printf.sprintf ".ditz/issue-%s.yaml" id)
                              ~content:(Printf.sprintf "id: %s\n" id) ~commit_msg:id) in
  (try
    Sys.chdir c1;
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"R") in
    write "r1"; write "r2";
    assert (state () = Git.No_remote_branch);
    let n_local = int_of_string (assert_ok (Git.git ["rev-list"; "--count"; "ditz-metadata"])) in
    (* the first push of a never-pushed branch must not depend on git's
       (translatable) error text; best effort -- only discriminating where
       git's translations are installed *)
    let saved = List.map (fun v -> (v, Sys.getenv_opt v)) ["LANGUAGE"; "LC_ALL"; "LANG"] in
    Unix.putenv "LANGUAGE" "de"; Unix.putenv "LC_ALL" "de_DE.UTF-8"; Unix.putenv "LANG" "de_DE.UTF-8";
    let r = Git.sync_report () in
    List.iter (fun (v, old) -> Unix.putenv v (Option.value old ~default:"")) saved;
    let r = assert_ok r in
    assert (r.pulled = 0 && r.pushed = n_local);
    assert (tracking 0 0);
    (* pushed comes from what git actually did, not a stale tracking ref *)
    run_in ~cwd:c1 "git update-ref refs/remotes/origin/ditz-metadata ditz-metadata~1";
    let r = assert_ok (Git.push_report ()) in
    assert (r.pushed = 0);
    assert (tracking 0 0);
    (* sync_state is read-only: in a clone that has fetched but never synced
       it reports everything as behind, without creating the local branch *)
    Sys.chdir c2;
    run_in ~cwd:c2 "git fetch origin";
    assert (tracking 0 n_local);
    assert (not (Git.branch_exists "ditz-metadata"));
    (* fresh clone: the whole branch is what the pull brings in *)
    let r = assert_ok (Git.sync_report ()) in
    assert (r.pulled = n_local && r.pushed = 0);
    assert (tracking 0 0);
    (* an unpushed write shows as ahead; the push reports it and clears it *)
    Sys.chdir c1;
    write "r3";
    assert (tracking 1 0);
    let r = assert_ok (Git.sync_report ()) in
    assert (r.pulled = 0 && r.pushed = 1);
    assert (tracking 0 0);
    (* the other clone pulls exactly that commit *)
    Sys.chdir c2;
    let r = assert_ok (Git.sync_report ()) in
    assert (r.pulled = 1 && r.pushed = 0);
    ignore (assert_ok (Git.read_file_from_branch ".ditz/issue-r3.yaml"));
    assert (tracking 0 0);
    (* pull-only leaves local work unpushed, and says so via state *)
    write "r4";
    let r = assert_ok (Git.pull_report ()) in
    assert (r.pulled = 0 && r.pushed = 0);
    assert (tracking 1 0);
    (* a remote.origin.push mapping can't divert the push *)
    run_in ~cwd:c2 "git config remote.origin.push refs/heads/ditz-metadata:refs/heads/elsewhere";
    let r = assert_ok (Git.push_report ()) in
    assert (r.pushed = 1);
    let remote_head = assert_ok (Git.git ["ls-remote"; "origin"; "refs/heads/ditz-metadata"]) in
    let local_head = assert_ok (Git.git ["rev-parse"; "ditz-metadata"]) in
    assert (String.sub remote_head 0 40 = local_head);
    assert (assert_ok (Git.git ["ls-remote"; "origin"; "refs/heads/elsewhere"]) = "");
    cleanup ()
  with e -> cleanup (); raise e);
  Printf.printf "PASS: sync_reports_and_state\n"

let test_sync_conflict_escape_hatch () =
  let origin, c1, c2 = make_cloned_pair "ditz_synchard" in
  let old_cwd = Sys.getcwd () in
  let cleanup () = Sys.chdir old_cwd; rm_rf origin; rm_rf c1; rm_rf c2 in
  (try
    let created = [ ("2026-06-01T00:00:00-00:00", "created", "\"\"") ] in
    Sys.chdir c1;
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"S") in
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-sync2.yaml"
      ~content:(sync_issue_yaml ~id:"sync2" ~title:"Base title" ~status:"Unstarted" ~events:created)
      ~commit_msg:"base") in
    let () = assert_ok (Git.sync ()) in
    Sys.chdir c2;
    run_in ~cwd:c2 "git fetch origin";
    (* local branch auto-created by ensure_local_branch now; no workaround *)
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-sync2.yaml"
      ~content:(sync_issue_yaml ~id:"sync2" ~title:"Title from c2" ~status:"Unstarted" ~events:created)
      ~commit_msg:"retitle on clone2") in
    Sys.chdir c1;
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-sync2.yaml"
      ~content:(sync_issue_yaml ~id:"sync2" ~title:"Title from c1" ~status:"Unstarted" ~events:created)
      ~commit_msg:"retitle on clone1") in
    let () = assert_ok (Git.sync ()) in
    (* clone2: both sides changed the title -> sync must refuse, abort the
       merge, leave LOCAL/REMOTE copies, and not move the local branch *)
    Sys.chdir c2;
    let before = match Git.git ["rev-parse"; "ditz-metadata"] with
      | Ok r -> r | Error (`Msg e) -> failwith e in
    (match Git.sync () with
     | Ok () -> failwith "expected sync to fail on double title change"
     | Error (`Msg m) ->
       assert (contains m "issue-sync2.yaml");
       assert (contains m "title"));
    let after = match Git.git ["rev-parse"; "ditz-metadata"] with
      | Ok r -> r | Error (`Msg e) -> failwith e in
    assert (before = after);
    let conflict_dir = Filename.concat c2 ".ditz-conflict" in
    assert (Sys.file_exists (Filename.concat conflict_dir "issue-sync2.yaml.LOCAL"));
    assert (Sys.file_exists (Filename.concat conflict_dir "issue-sync2.yaml.REMOTE"));
    (* the metadata worktree is not left mid-merge *)
    let wt = match Git.persistent_worktree_path () with
      | Some p -> p | None -> failwith "no worktree path" in
    (match Git.git ~cwd:wt ["rev-parse"; "-q"; "--verify"; "MERGE_HEAD"] with
     | Ok _ -> failwith "merge was left in progress"
     | Error _ -> ());
    cleanup ()
  with e -> cleanup (); raise e);
  Printf.printf "PASS: sync_conflict_escape_hatch\n"

let test_fresh_clone_can_join () =
  let origin, c1, c2 = make_cloned_pair "ditz_onboard" in
  let old_cwd = Sys.getcwd () in
  let cleanup () = Sys.chdir old_cwd; rm_rf origin; rm_rf c1; rm_rf c2 in
  (try
    (* c1 creates the tracker + an issue and pushes to origin. *)
    Sys.chdir c1;
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"Onboard") in
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-shared.yaml"
      ~content:"id: shared\ntitle: Shared\n" ~commit_msg:"base") in
    let () = assert_ok (Git.sync ()) in
    (* c2 is a FRESH clone: after fetch it has origin/ditz-metadata but NO local
       branch — and crucially we do NOT run the old `git branch` workaround. *)
    Sys.chdir c2;
    run_in ~cwd:c2 "git fetch origin";
    assert (not (Git.branch_exists "ditz-metadata"));
    assert (Git.branch_exists ~remote:true "ditz-metadata");
    (* read: list finds the shared issue (would be [] without the fix) *)
    let files = Git.list_ditz_files () in
    assert (List.exists (fun f -> Filename.basename f = "issue-shared.yaml") files);
    (* the local branch was auto-created by the read *)
    assert (Git.branch_exists "ditz-metadata");
    (* write also works from the fresh clone *)
    let () = assert_ok (Git.write_to_branch
      ~path:".ditz/issue-fromc2.yaml"
      ~content:"id: fromc2\ntitle: From C2\n" ~commit_msg:"c2 add") in
    let content = assert_ok (Git.read_file_from_branch ".ditz/issue-fromc2.yaml") in
    assert (contains content "fromc2");
    cleanup ()
  with e -> cleanup (); raise e);
  Printf.printf "PASS: fresh_clone_can_join\n"

let test_push_only_fresh_clone () =
  let origin, c1, c2 = make_cloned_pair "ditz_pushonly" in
  let old_cwd = Sys.getcwd () in
  let cleanup () = Sys.chdir old_cwd; rm_rf origin; rm_rf c1; rm_rf c2 in
  (try
    Sys.chdir c1;
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"P") in
    let () = assert_ok (Git.sync ()) in
    (* c2: fresh clone, fetched, NO local branch — `push` (sync --push-only)
       must materialize the local branch from origin and not fail. *)
    Sys.chdir c2;
    run_in ~cwd:c2 "git fetch origin";
    assert (not (Git.branch_exists "ditz-metadata"));
    let () = assert_ok (Git.push ()) in
    assert (Git.branch_exists "ditz-metadata");
    cleanup ()
  with e -> cleanup (); raise e);
  Printf.printf "PASS: push_only_fresh_clone\n"

let test_submodule_refused () =
  let super = make_temp_dir "ditz_super" in
  let sub = make_temp_dir "ditz_sub" in
  let old_cwd = Sys.getcwd () in
  let cleanup () = Sys.chdir old_cwd; rm_rf super; rm_rf sub in
  (try
    init_git_repo sub;
    init_git_repo super;
    run_in ~cwd:super
      (Printf.sprintf "git -c protocol.file.allow=always submodule add %s subm"
        (Filename.quote sub));
    run_in ~cwd:super "git commit -m 'add submodule'";
    Sys.chdir (Filename.concat super "subm");
    assert (Git.in_submodule ());
    (* both create paths refuse cleanly (for the submodule reason, not some
       other failure) rather than landing state in <super>/.git/modules/subm *)
    let mentions_submodule = function
      | Error (`Msg m) -> contains m "submodule"
      | Ok _ -> false
    in
    assert (mentions_submodule (Git.create_ditz_metadata_branch ~project_name:"X"));
    assert (mentions_submodule (Git.create_persistent_worktree ()));
    cleanup ()
  with e -> cleanup (); raise e);
  Printf.printf "PASS: submodule_refused\n"

let test_submodule_no_false_positive () =
  (* A normal repo whose PATH merely contains ".git/modules" must NOT be taken
     for a submodule (the old substring check got this wrong). *)
  let base = make_temp_dir "ditz_fp" in
  let nested = Filename.concat base ".git/modules/foo" in
  let old_cwd = Sys.getcwd () in
  let cleanup () = Sys.chdir old_cwd; rm_rf base in
  (try
    let _ = Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote nested)) in
    init_git_repo nested;
    Sys.chdir nested;
    assert (not (Git.in_submodule ()));
    let () = assert_ok (Git.create_ditz_metadata_branch ~project_name:"FP") in
    assert (Git.ditz_metadata_exists ());
    cleanup ()
  with e -> cleanup (); raise e);
  Printf.printf "PASS: submodule_no_false_positive\n"

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
  test_write_commits_only_its_path ();
  test_failed_write_rolls_back ();
  test_persistent_worktree ();
  test_ephemeral_worktree ();
  test_find_common_root ();
  test_find_common_root_from_subdirectory ();
  test_find_existing_ditz_worktree ();
  test_persistent_worktree_from_external_worktree ();
  test_persistent_worktree_from_inside_ditz_worktree ();
  test_write_from_external_worktree ();
  test_bare_at_root_layout ();
  test_foreign_worktree_rejected ();
  test_list_from_subdirectory ();
  test_stale_worktree_self_heal ();
  test_self_heal_spares_other_worktrees ();
  test_write_does_not_follow_symlink ();
  test_sync_auto_resolves_divergence ();
  test_sync_conflict_escape_hatch ();
  test_sync_names_staged_leftovers ();
  test_sync_pulls_without_fetch_refspec ();
  test_sync_reports_and_state ();
  test_fresh_clone_can_join ();
  test_push_only_fresh_clone ();
  test_submodule_refused ();
  test_submodule_no_false_positive ();
  test_storage_git_backend ();
  Printf.printf "\nAll git integration tests passed!\n"
