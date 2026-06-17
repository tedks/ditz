(** Git integration for ditz - reads/writes from ditz-metadata branch *)

let ditz_branch = "ditz-metadata"
let worktree_dir = ".ditz-worktree"

(** Check if using ephemeral worktree mode (old behavior) *)
let use_ephemeral_worktree () =
  match Sys.getenv_opt "DITZ_EPHEMERAL_WORKTREE" with
  | Some "1" | Some "true" -> true
  | _ -> false

(** Run a git command and return stdout, stderr, and exit code.
    ignore_repo_env strips GIT_DIR/GIT_WORK_TREE so the command describes the
    repository at cwd, not whatever the environment points at — required when
    inspecting a candidate directory rather than operating on "our" repo. *)
let run_git_command ?(cwd = ".") ?(ignore_repo_env = false) args =
  let base = String.concat " " ("git" :: List.map Filename.quote args) in
  let cmd =
    if ignore_repo_env then "env -u GIT_DIR -u GIT_WORK_TREE " ^ base else base
  in
  let stdout_file = Filename.temp_file "ditz_git_stdout" ".txt" in
  let stderr_file = Filename.temp_file "ditz_git_stderr" ".txt" in
  let full_cmd = Printf.sprintf "cd %s && %s > %s 2> %s"
    (Filename.quote cwd) cmd (Filename.quote stdout_file) (Filename.quote stderr_file) in
  let exit_code = Sys.command full_cmd in
  let read_file path =
    if Sys.file_exists path then begin
      let content = Fs_util.read_file path in
      Sys.remove path;
      String.trim content
    end else ""
  in
  let stdout_content = read_file stdout_file in
  let stderr_content = read_file stderr_file in
  (stdout_content, stderr_content, exit_code)

(** Run git command and return Ok stdout or Error stderr *)
let git ?(cwd = ".") ?(ignore_repo_env = false) args =
  let (stdout, stderr, code) = run_git_command ~cwd ~ignore_repo_env args in
  if code = 0 then Ok stdout
  else Error (`Msg (Printf.sprintf "git %s failed: %s" (String.concat " " args) stderr))

(** Get a git config value *)
let get_config key =
  git ["config"; key]

(** Find the root of the current worktree (varies per worktree) *)
let find_git_root () =
  match git ["rev-parse"; "--show-toplevel"] with
  | Ok path -> Some path
  | Error _ -> None

(** Find the shared .git directory (same for all worktrees).
    git rev-parse --git-common-dir may return a relative path,
    so we resolve it to absolute. *)
let find_common_git_dir () =
  match git ["rev-parse"; "--git-common-dir"] with
  | Ok path ->
    let abs_path =
      if Filename.is_relative path then
        Filename.concat (Sys.getcwd ()) path
      else
        path
    in
    (try Some (Unix.realpath abs_path) with Unix.Unix_error _ -> Some abs_path)
  | Error _ -> None

(** Find the stable container directory that's the same from every worktree.
    For a normal repo the common git dir is <root>/.git, so the container is
    its parent. For a bare repo the common git dir IS the repo — using its
    parent would place .ditz-worktree outside the repository, shared with (and
    corrupted by) any sibling bare repo under the same parent directory.
    Submodules are refused (see [in_submodule]): inside one the common dir is
    <super>/.git/modules/<name>, so the container would land inside the
    superproject's git dir — repo-unique but removed wholesale by
    `git submodule deinit`. Rather than silently create fragile state there,
    the worktree-creation paths refuse with a clear message. *)
let find_common_root () =
  match find_common_git_dir () with
  | Some dir ->
    if Filename.basename dir = ".git" then Some (Filename.dirname dir)
    else Some dir
  | None -> None

(* Inside a git submodule? A submodule's state lives in <super>/.git/modules/...
   which is fragile (git submodule deinit / absorbgitdirs would take it), so we
   refuse rather than create ditz state there. tedks has no submodules; this is
   a clean failure for an unsupported edge, not a feature.
   `--show-superproject-working-tree` prints the superproject's worktree iff
   this repo is a submodule, and nothing otherwise — exact, unlike a path
   substring that would false-positive on a repo merely rooted under some
   ".git/modules/" path. *)
let in_submodule () =
  match git ["rev-parse"; "--show-superproject-working-tree"] with
  | Ok out -> String.trim out <> ""
  | Error _ -> false

let submodule_error =
  Error (`Msg "ditz inside a git submodule is not supported (its .git/modules \
               dir is unstable); run ditz in the superproject instead")

(** Parse `git worktree list --porcelain` to find an existing worktree
    checked out on the ditz-metadata branch. Returns Some path or None.
    Entries whose directory was deleted out from under git ("prunable") are
    skipped — returning one would wedge every write until a manual
    `git worktree prune`. Stale ditz registrations are removed SURGICALLY
    (`git worktree remove --force <path>`), never via a global prune: a
    global prune would also destroy unrelated registrations that are merely
    unreachable right now (a worktree the user mv'd and could repair, or one
    on unmounted storage), and that loss is unrecoverable. *)
let find_existing_ditz_worktree () =
  match git ["worktree"; "list"; "--porcelain"] with
  | Error _ -> None
  | Ok output ->
    let target_branch = "branch refs/heads/" ^ ditz_branch in
    (* Group lines into per-worktree entries (separated by blank lines) *)
    let entries =
      String.split_on_char '\n' output
      |> List.map String.trim
      |> List.fold_left (fun groups line ->
          match groups with
          | _ when line = "" -> [] :: groups
          | [] -> [[line]]
          | cur :: rest -> (line :: cur) :: rest)
        []
      |> List.map List.rev
    in
    let prefixed prefix l =
      String.length l >= String.length prefix
      && String.sub l 0 (String.length prefix) = prefix
    in
    let parsed =
      List.filter_map (fun entry ->
        let path =
          List.find_map (fun l ->
            if prefixed "worktree " l then
              Some (String.sub l 9 (String.length l - 9))
            else None)
            entry
        in
        let on_target = List.mem target_branch entry in
        let prunable =
          List.exists (fun l -> l = "prunable" || prefixed "prunable " l) entry
        in
        Option.map (fun p -> (p, on_target, prunable)) path)
        entries
    in
    let candidates =
      List.filter_map
        (fun (p, on_target, prunable) -> if on_target then Some (p, prunable) else None)
        parsed
    in
    match
      List.find_opt (fun (p, prunable) -> not prunable && Sys.file_exists p) candidates
    with
    | Some (path, _) -> Some path
    | None ->
      let other_prunable =
        List.exists (fun (_, on_target, prunable) -> (not on_target) && prunable) parsed
      in
      List.iter
        (fun (p, _) ->
          match git ["worktree"; "remove"; "--force"; p] with
          | Ok _ -> ()
          | Error _ ->
            (* Older git may refuse to remove a missing-dir registration.
               Global prune is a last resort, and only when it cannot take
               anyone else's registration with it. *)
            if not other_prunable then ignore (git ["worktree"; "prune"]))
        candidates;
      None

(** Check if we're in a git repository *)
let is_git_repo () =
  match git ["rev-parse"; "--git-dir"] with
  | Ok _ -> true
  | Error _ -> false

(** Check if the ditz-metadata branch exists locally *)
let branch_exists ?(remote = false) branch =
  let ref_name = if remote then "refs/remotes/origin/" ^ branch else "refs/heads/" ^ branch in
  match git ["show-ref"; "--verify"; "--quiet"; ref_name] with
  | Ok _ -> true
  | Error _ -> false

(** Check if ditz-metadata branch exists (locally or on remote) *)
let ditz_metadata_exists () =
  branch_exists ditz_branch || branch_exists ~remote:true ditz_branch

(** A fresh clone has only origin/ditz-metadata and no local branch — but every
    read/write resolves the LOCAL [ditz_branch] ref, so without this the tracker
    looks empty and writes fail ("invalid reference"). Create the local branch
    from origin the first time it's needed. Idempotent: no-op when the local
    branch already exists or there is no remote branch to track. *)
let ensure_local_branch () =
  if (not (branch_exists ditz_branch)) && branch_exists ~remote:true ditz_branch then
    ignore (git ["branch"; ditz_branch; "origin/" ^ ditz_branch])

(** Get path to persistent worktree.
    First checks for an existing ditz-metadata worktree (via git worktree list),
    then falls back to <common-root>/.ditz-worktree. *)
let persistent_worktree_path () =
  match find_existing_ditz_worktree () with
  | Some path -> Some path
  | None ->
    match find_common_root () with
    | Some root -> Some (Filename.concat root worktree_dir)
    | None -> None

(** Check if persistent worktree exists and is valid: on the ditz-metadata
    branch AND belonging to THIS repository. The ownership check matters: a
    directory that is some other repo's ditz worktree would otherwise pass,
    and writes would land in that other project's tracker. *)
let persistent_worktree_valid () =
  match persistent_worktree_path () with
  | None -> false
  | Some path ->
    Sys.file_exists path && Sys.is_directory path
    && (match git ~cwd:path ~ignore_repo_env:true ["rev-parse"; "--abbrev-ref"; "HEAD"] with
        | Ok branch -> String.trim branch = ditz_branch
        | Error _ -> false)
    && (match git ~cwd:path ~ignore_repo_env:true ["rev-parse"; "--git-common-dir"], find_common_git_dir () with
        | Ok wt_common, Some our_common ->
          let abs =
            if Filename.is_relative wt_common then Filename.concat path wt_common
            else wt_common
          in
          let resolved = (try Unix.realpath abs with Unix.Unix_error _ -> abs) in
          resolved = our_common
        | _ -> false)

(** Create persistent worktree with sparse checkout *)
let create_persistent_worktree () =
  if in_submodule () then submodule_error
  else
  match persistent_worktree_path () with
  | None -> Error (`Msg "Not in a git repository")
  | Some path ->
    if Sys.file_exists path then
      (* Already exists, verify it's correct *)
      if persistent_worktree_valid () then Ok path
      else Error (`Msg (Printf.sprintf
        "%s exists but is not a checkout of %s (wrong branch, detached HEAD, or \
         another repo's worktree). Remove it (git worktree remove --force) and retry."
        path ditz_branch))
    else
      (* Create the worktree *)
      match git ["worktree"; "add"; path; ditz_branch] with
      | Error e -> Error e
      | Ok _ ->
        (* Set up sparse checkout to only include .ditz *)
        match git ~cwd:path ["sparse-checkout"; "init"; "--cone"] with
        | Error e -> Error e
        | Ok _ ->
          match git ~cwd:path ["sparse-checkout"; "set"; ".ditz"] with
          | Error e -> Error e
          | Ok _ -> Ok path

(** Ensure persistent worktree exists, create if needed *)
let ensure_persistent_worktree () =
  if persistent_worktree_valid () then
    match persistent_worktree_path () with
    | Some path -> Ok path
    | None -> Error (`Msg "Not in a git repository")
  else
    create_persistent_worktree ()

(** Execute a function with a worktree path. Uses persistent worktree by default,
    or ephemeral worktree if DITZ_EPHEMERAL_WORKTREE=1 and no persistent worktree exists.
    Note: git only allows one worktree per branch, so if persistent exists we must use it. *)
let with_worktree f =
  (* A fresh clone needs its local branch before a worktree can be added. *)
  ensure_local_branch ();
  (* If persistent worktree exists, always use it (git won't allow a second worktree) *)
  if persistent_worktree_valid () then
    match persistent_worktree_path () with
    | Some path -> f path
    | None -> Error (`Msg "Not in a git repository")
  else if use_ephemeral_worktree () then
    (* Ephemeral mode: create temp worktree, use it, remove it *)
    let temp_dir = Filename.temp_file "ditz_worktree" "" in
    Sys.remove temp_dir;
    match git ["worktree"; "add"; temp_dir; ditz_branch] with
    | Error e -> Error e
    | Ok _ ->
      let result = f temp_dir in
      let _ = git ["worktree"; "remove"; "--force"; temp_dir] in
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote temp_dir)) in
      result
  else
    (* Default: create and use persistent worktree *)
    match ensure_persistent_worktree () with
    | Error e -> Error e
    | Ok path -> f path

(** Create the ditz-metadata orphan branch with initial project structure *)
let create_ditz_metadata_branch ~project_name =
  (* find_git_root requires a work tree and so is false at a bare repo root;
     is_git_repo holds anywhere inside the repository. Error, never failwith. *)
  if in_submodule () then submodule_error
  else if not (is_git_repo ()) then Error (`Msg "Not in a git repository")
  else
  let temp_dir = Filename.temp_file "ditz_init" "" in
  Sys.remove temp_dir;

  (* Create the orphan branch using git checkout --orphan in a temp worktree *)
  match git ["worktree"; "add"; "--detach"; temp_dir; "HEAD"] with
  | Error e -> Error e
  | Ok _ ->
    (* Fun.protect: an exception while populating the worktree (Unix.mkdir,
       a write, ...) must still remove the temp worktree, not leak it. *)
    Fun.protect
      ~finally:(fun () ->
        let _ = git ["worktree"; "remove"; "--force"; temp_dir] in
        let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote temp_dir)) in
        ())
    @@ fun () ->
      match git ~cwd:temp_dir ["checkout"; "--orphan"; ditz_branch] with
      | Error e -> Error e
      | Ok _ ->
        (* Remove all files from index *)
        let _ = git ~cwd:temp_dir ["rm"; "-rf"; "--cached"; "."] in
        let _ = Sys.command (Printf.sprintf "rm -rf %s/*" (Filename.quote temp_dir)) in

        (* Create .ditz directory with project.yaml *)
        let ditz_dir = Filename.concat temp_dir ".ditz" in
        Unix.mkdir ditz_dir 0o755;

        let project_yaml = Printf.sprintf {|name: %s
version: "0.1.0"
components:
- name: %s
releases: []
|} project_name project_name in

        let project_file = Filename.concat ditz_dir "project.yaml" in
        match Fs_util.write_file_atomic ~path:project_file ~content:project_yaml with
        | Error e -> Error e
        | Ok () ->
          (* Add and commit *)
          match git ~cwd:temp_dir ["add"; ".ditz"] with
          | Error e -> Error e
          | Ok _ ->
            match git ~cwd:temp_dir ["commit"; "-m"; "ditz: initialize issue tracker"] with
            | Error e -> Error e
            | Ok _ -> Ok ()

(** Read a file from the ditz-metadata branch without checkout *)
let read_file_from_branch path =
  ensure_local_branch ();
  let ref_path = ditz_branch ^ ":" ^ path in
  git ["show"; ref_path]

(** List files in .ditz directory on ditz-metadata branch.
    --full-tree is load-bearing: ls-tree implicitly limits output to the
    cwd-derived prefix, so without it this silently returns [] (exit 0)
    when run from any subdirectory of a worktree. *)
let list_ditz_files () =
  ensure_local_branch ();
  match git ["ls-tree"; "--full-tree"; "--name-only"; ditz_branch ^ ":.ditz"] with
  | Ok output ->
    if output = "" then []
    else
      String.split_on_char '\n' output
      |> List.filter (fun l -> String.trim l <> "")
      |> List.map (fun name -> ".ditz/" ^ String.trim name)
  | Error _ -> []

(** Write content to a file on ditz-metadata branch using worktree.
    The write is atomic (temp + rename) and does not follow a symlink planted
    at the destination -- issue files are parsed from external sources, so the
    write path must not be steerable. *)
let write_to_branch ~path ~content ~commit_msg =
  with_worktree (fun worktree_path ->
    (* Write the file *)
    let full_path = Filename.concat worktree_path path in
    let dir = Filename.dirname full_path in
    let _ = Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)) in
    match Fs_util.write_file_atomic ~path:full_path ~content with
    | Error e -> Error e
    | Ok () ->

    (* Add and commit *)
    match git ~cwd:worktree_path ["add"; path] with
    | Error e -> Error e
    | Ok _ ->
      (* Check if there are changes to commit *)
      match git ~cwd:worktree_path ["diff"; "--cached"; "--quiet"] with
      | Ok _ -> Ok () (* No changes staged, nothing to commit *)
      | Error _ ->
        (* There are staged changes, commit them *)
        match git ~cwd:worktree_path ["commit"; "-m"; commit_msg] with
        | Error e -> Error e
        | Ok _ -> Ok ()
  )

(** Delete a file from ditz-metadata branch *)
let delete_from_branch ~path ~commit_msg =
  with_worktree (fun worktree_path ->
    let full_path = Filename.concat worktree_path path in
    if Sys.file_exists full_path then begin
      Sys.remove full_path;
      match git ~cwd:worktree_path ["add"; path] with
      | Error e -> Error e
      | Ok _ ->
        match git ~cwd:worktree_path ["commit"; "-m"; commit_msg] with
        | Error e -> Error e
        | Ok _ -> Ok ()
    end else
      Error (`Msg (Printf.sprintf "File %s not found" path))
  )

(** Fetch ditz-metadata from origin *)
let fetch () =
  match git ["fetch"; "origin"; ditz_branch] with
  | Ok _ -> Ok ()
  | Error _ ->
    (* Branch might not exist on remote yet, that's OK *)
    Ok ()

(** Auto-resolve a conflicted merge inside the metadata worktree.
    Conflicted issue files are merged semantically (Merge.merge_issues, using
    git's base/ours/theirs index stages). Delete/modify keeps the modified
    side — a concurrent edit beats a drop, resurrecting beats losing data.
    Anything that cannot be auto-resolved (project.yaml, unparseable files,
    title/desc changed on both sides) aborts the whole merge — the tracker is
    never left half-merged — and LOCAL/REMOTE copies are written under
    .ditz-conflict/ in the caller's cwd for manual resolution. *)
let resolve_conflicted_merge ~merge_error worktree_path =
  (* Returns whether the abort actually succeeded — claiming "merge aborted"
     when it wasn't would point the user away from the real problem. *)
  let abort () =
    match git ~cwd:worktree_path ["merge"; "--abort"] with
    | Ok _ -> true
    | Error _ -> false
  in
  let abort_note aborted =
    if aborted then ""
    else
      Printf.sprintf
        " (WARNING: 'git merge --abort' also failed; the metadata worktree at \
         %s is still mid-merge and needs manual attention)"
        worktree_path
  in
  let show_stage stage file =
    match git ~cwd:worktree_path ["show"; Printf.sprintf ":%d:%s" stage file] with
    | Ok content -> Some content
    | Error _ -> None
  in
  (* The stages that actually exist for a conflicted path, from ls-files -u
     ("<mode> <sha> <stage>\t<path>"). A `git show` failure for a LISTED
     stage is a hard failure for that file — treating it as "stage absent"
     would silently reclassify a modify/modify conflict as delete/modify and
     drop one side's content. *)
  let stages_of file =
    match git ~cwd:worktree_path ["ls-files"; "-u"; "--"; file] with
    | Error (`Msg e) -> Error e
    | Ok out ->
      Ok
        (String.split_on_char '\n' out
         |> List.filter_map (fun line ->
             match String.split_on_char '\t' line with
             | meta :: _ ->
               (match String.split_on_char ' ' (String.trim meta) with
                | [ _mode; _sha; stage ] -> int_of_string_opt stage
                | _ -> None)
             | [] -> None))
  in
  let is_issue_file file =
    Filename.dirname file = ".ditz"
    && (let b = Filename.basename file in
        String.length b > 6 && String.sub b 0 6 = "issue-"
        && Filename.check_suffix b ".yaml")
  in
  let stage_resolved file content =
    match Fs_util.write_file_atomic
            ~path:(Filename.concat worktree_path file) ~content with
    | Error (`Msg e) -> Error e
    | Ok () ->
      (match git ~cwd:worktree_path ["add"; "--"; file] with
       | Ok _ -> Ok ()
       | Error (`Msg e) -> Error e)
  in
  let resolve_file file =
    match stages_of file with
    | Error e -> Error (file, e, None, None)
    | Ok stages ->
      let fetch n =
        if List.mem n stages then
          match show_stage n file with
          | Some c -> Ok (Some c)
          | None -> Error (Printf.sprintf "git show :%d failed for a listed stage" n)
        else Ok None
      in
      (match fetch 2, fetch 3 with
       | Error e, _ | _, Error e -> Error (file, e, None, None)
       | Ok ours, Ok theirs ->
         let fail reason = Error (file, reason, ours, theirs) in
         (match ours, theirs with
          | None, None ->
            (match git ~cwd:worktree_path ["rm"; "--quiet"; "--"; file] with
             | Ok _ -> Ok ()
             | Error (`Msg e) -> fail e)
          | Some content, None | None, Some content ->
            (* delete/modify conflict: keep the modified side *)
            (match stage_resolved file content with
             | Ok () -> Ok ()
             | Error e -> fail e)
          | Some ours_s, Some theirs_s ->
            if not (is_issue_file file) then
              fail "not an issue file; cannot auto-resolve"
            else
              (match fetch 1 with
               | Error e -> fail e
               | Ok base_s ->
                 (* An EXISTING but unparseable base must hard-fail: silently
                    degrading to base-less union mode would resurrect entries
                    one side deliberately deleted. *)
                 let base_result =
                   match base_s with
                   | None -> Ok None
                   | Some s ->
                     (match Merge.issue_of_string s with
                      | Ok b -> Ok (Some b)
                      | Error (`Msg e) -> Error ("base version unparseable: " ^ e))
                 in
                 match base_result with
                 | Error e -> fail e
                 | Ok base ->
                 (match Merge.issue_of_string ours_s, Merge.issue_of_string theirs_s with
                  | Ok o, Ok t ->
                    (match Merge.merge_issues ~base ~ours:o ~theirs:t with
                     | Ok merged ->
                       (match Merge.issue_to_string merged with
                        | Error (`Msg e) -> fail ("serialize failed: " ^ e)
                        | Ok content ->
                          (match stage_resolved file content with
                           | Ok () -> Ok ()
                           | Error e -> fail e))
                     | Error fieldname -> fail ("both sides changed " ^ fieldname))
                  | Error (`Msg e), _ | _, Error (`Msg e) ->
                    fail ("unparseable: " ^ e)))))
  in
  let with_note result =
    match result with
    | Ok () -> Ok ()
    | Error (`Msg m) ->
      let aborted = abort () in
      Error (`Msg (m ^ abort_note aborted))
  in
  match git ~cwd:worktree_path ["diff"; "--name-only"; "--diff-filter=U"] with
  | Error e -> with_note (Error e)
  | Ok out ->
    let files =
      String.split_on_char '\n' out
      |> List.map String.trim
      |> List.filter (fun l -> l <> "")
    in
    if files = [] then
      (* The merge failed before producing conflicts (dirty worktree,
         lock...). The original git error is the actionable one. *)
      with_note merge_error
    else begin
      match
        List.filter_map
          (fun f -> match resolve_file f with Ok () -> None | Error x -> Some x)
          files
      with
      | [] ->
        (match git ~cwd:worktree_path ["commit"; "--no-edit"] with
         | Ok _ ->
           Logs.info (fun m ->
             m "ditz sync: auto-resolved %d conflicted file(s)" (List.length files));
           Ok ()
         | Error e -> with_note (Error e))
      | failures ->
        let conflict_dir = Filename.concat (Sys.getcwd ()) ".ditz-conflict" in
        let dumps_ok = ref true in
        (try Unix.mkdir conflict_dir 0o755
         with
         | Unix.Unix_error (Unix.EEXIST, _, _) -> ()
         | Unix.Unix_error _ -> dumps_ok := false);
        List.iter
          (fun (file, _reason, ours, theirs) ->
            let b = Filename.basename file in
            let dump suffix = function
              | None -> ()
              | Some content ->
                (match Fs_util.write_file_atomic
                         ~path:(Filename.concat conflict_dir (b ^ suffix))
                         ~content with
                 | Ok () -> ()
                 | Error _ -> dumps_ok := false)
            in
            dump ".LOCAL" ours;
            dump ".REMOTE" theirs)
          failures;
        let aborted = abort () in
        let detail =
          failures
          |> List.map (fun (f, r, _, _) -> Printf.sprintf "%s (%s)" f r)
          |> String.concat ", "
        in
        let copies =
          if !dumps_ok then
            Printf.sprintf "LOCAL/REMOTE copies are in %s" conflict_dir
          else
            Printf.sprintf
              "copies could NOT be written to %s (check permissions/contents)"
              conflict_dir
        in
        Error (`Msg (Printf.sprintf
          "Could not auto-resolve: %s. %s; the merge was %s — resolve manually \
           and re-run 'ditz sync'.%s"
          detail copies
          (if aborted then "aborted" else "NOT cleanly aborted")
          (abort_note aborted)))
    end

(** Merge origin/ditz-metadata into local ditz-metadata, auto-resolving
    conflicts where the semantics allow (see resolve_conflicted_merge).
    Any exception inside resolution aborts the merge first: the tracker is
    never left mid-merge, whatever goes wrong. *)
let merge () =
  if not (branch_exists ~remote:true ditz_branch) then
    Ok () (* Nothing to merge *)
  else
    with_worktree (fun worktree_path ->
      match git ~cwd:worktree_path ["merge"; "origin/" ^ ditz_branch; "-m"; "ditz: merge remote changes"] with
      | Ok _ -> Ok ()
      | Error e ->
        (try resolve_conflicted_merge ~merge_error:(Error e) worktree_path
         with exn ->
           let aborted =
             match git ~cwd:worktree_path ["merge"; "--abort"] with
             | Ok _ -> true
             | Error _ -> false
           in
           Error (`Msg (Printf.sprintf
             "sync conflict resolution failed unexpectedly (%s); merge %s"
             (Printexc.to_string exn)
             (if aborted then "aborted"
              else "NOT aborted — the metadata worktree needs manual attention"))))
    )

(** Push ditz-metadata to origin *)
let push () =
  (* On a fresh clone `sync --push-only` would have no local branch to push;
     materialize it from origin first (no-op if it already exists). *)
  ensure_local_branch ();
  match git ["push"; "-u"; "origin"; ditz_branch] with
  | Ok _ -> Ok ()
  | Error e -> Error e

(** Full sync: fetch, merge, push *)
let sync () =
  match fetch () with
  | Error e -> Error e
  | Ok () ->
    match merge () with
    | Error e -> Error e
    | Ok () -> push ()
