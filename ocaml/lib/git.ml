(** Git integration for ditz - reads/writes from ditz-metadata branch *)

let ditz_branch = "ditz-metadata"

(** Run a git command and return stdout, stderr, and exit code *)
let run_git_command ?(cwd = ".") args =
  let cmd = String.concat " " ("git" :: List.map Filename.quote args) in
  let stdout_file = Filename.temp_file "ditz_git_stdout" ".txt" in
  let stderr_file = Filename.temp_file "ditz_git_stderr" ".txt" in
  let full_cmd = Printf.sprintf "cd %s && %s > %s 2> %s"
    (Filename.quote cwd) cmd (Filename.quote stdout_file) (Filename.quote stderr_file) in
  let exit_code = Sys.command full_cmd in
  let read_file path =
    if Sys.file_exists path then begin
      let ic = open_in path in
      let content = really_input_string ic (in_channel_length ic) in
      close_in ic;
      Sys.remove path;
      String.trim content
    end else ""
  in
  let stdout_content = read_file stdout_file in
  let stderr_content = read_file stderr_file in
  (stdout_content, stderr_content, exit_code)

(** Run git command and return Ok stdout or Error stderr *)
let git ?(cwd = ".") args =
  let (stdout, stderr, code) = run_git_command ~cwd args in
  if code = 0 then Ok stdout
  else Error (`Msg (Printf.sprintf "git %s failed: %s" (String.concat " " args) stderr))

(** Get a git config value *)
let get_config key =
  git ["config"; key]

(** Find the root of the git repository *)
let find_git_root () =
  match git ["rev-parse"; "--show-toplevel"] with
  | Ok path -> Some path
  | Error _ -> None

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

(** Create the ditz-metadata orphan branch with initial project structure *)
let create_ditz_metadata_branch ~project_name =
  (* Create orphan branch using git worktree *)
  let _git_root = match find_git_root () with
    | Some _ -> ()
    | None -> failwith "Not in a git repository"
  in
  let temp_dir = Filename.temp_file "ditz_init" "" in
  Sys.remove temp_dir;

  (* Create the orphan branch using git checkout --orphan in a temp worktree *)
  match git ["worktree"; "add"; "--detach"; temp_dir; "HEAD"] with
  | Error e -> Error e
  | Ok _ ->
    (* Now in the worktree, create orphan branch *)
    let result =
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
        let oc = open_out project_file in
        output_string oc project_yaml;
        close_out oc;

        (* Add and commit *)
        match git ~cwd:temp_dir ["add"; ".ditz"] with
        | Error e -> Error e
        | Ok _ ->
          match git ~cwd:temp_dir ["commit"; "-m"; "ditz: initialize issue tracker"] with
          | Error e -> Error e
          | Ok _ -> Ok ()
    in
    (* Clean up worktree *)
    let _ = git ["worktree"; "remove"; "--force"; temp_dir] in
    (* Ensure the temp directory is cleaned up *)
    let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote temp_dir)) in
    result

(** Read a file from the ditz-metadata branch without checkout *)
let read_file_from_branch path =
  let ref_path = ditz_branch ^ ":" ^ path in
  git ["show"; ref_path]

(** List files in .ditz directory on ditz-metadata branch *)
let list_ditz_files () =
  match git ["ls-tree"; "--name-only"; ditz_branch; ".ditz/"] with
  | Ok output ->
    if output = "" then []
    else String.split_on_char '\n' output
  | Error _ -> []

(** Write content to a file on ditz-metadata branch using git worktree *)
let write_to_branch ~path ~content ~commit_msg =
  let _git_root = match find_git_root () with
    | Some r -> r
    | None -> failwith "Not in a git repository"
  in
  let temp_dir = Filename.temp_file "ditz_write" "" in
  Sys.remove temp_dir;

  match git ["worktree"; "add"; temp_dir; ditz_branch] with
  | Error e -> Error e
  | Ok _ ->
    let result =
      (* Write the file *)
      let full_path = Filename.concat temp_dir path in
      let dir = Filename.dirname full_path in
      let _ = Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)) in
      let oc = open_out full_path in
      output_string oc content;
      close_out oc;

      (* Add and commit *)
      match git ~cwd:temp_dir ["add"; path] with
      | Error e -> Error e
      | Ok _ ->
        (* Check if there are changes to commit *)
        match git ~cwd:temp_dir ["diff"; "--cached"; "--quiet"] with
        | Ok _ -> Ok () (* No changes staged, nothing to commit *)
        | Error _ ->
          (* There are staged changes, commit them *)
          match git ~cwd:temp_dir ["commit"; "-m"; commit_msg] with
          | Error e -> Error e
          | Ok _ -> Ok ()
    in
    (* Clean up worktree *)
    let _ = git ["worktree"; "remove"; "--force"; temp_dir] in
    let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote temp_dir)) in
    result

(** Delete a file from ditz-metadata branch *)
let delete_from_branch ~path ~commit_msg =
  let temp_dir = Filename.temp_file "ditz_delete" "" in
  Sys.remove temp_dir;

  match git ["worktree"; "add"; temp_dir; ditz_branch] with
  | Error e -> Error e
  | Ok _ ->
    let result =
      let full_path = Filename.concat temp_dir path in
      if Sys.file_exists full_path then begin
        Sys.remove full_path;
        match git ~cwd:temp_dir ["add"; path] with
        | Error e -> Error e
        | Ok _ ->
          match git ~cwd:temp_dir ["commit"; "-m"; commit_msg] with
          | Error e -> Error e
          | Ok _ -> Ok ()
      end else
        Error (`Msg (Printf.sprintf "File %s not found" path))
    in
    let _ = git ["worktree"; "remove"; "--force"; temp_dir] in
    let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote temp_dir)) in
    result

(** Fetch ditz-metadata from origin *)
let fetch () =
  match git ["fetch"; "origin"; ditz_branch] with
  | Ok _ -> Ok ()
  | Error _ ->
    (* Branch might not exist on remote yet, that's OK *)
    Ok ()

(** Merge origin/ditz-metadata into local ditz-metadata *)
let merge () =
  if not (branch_exists ~remote:true ditz_branch) then
    Ok () (* Nothing to merge *)
  else begin
    let temp_dir = Filename.temp_file "ditz_merge" "" in
    Sys.remove temp_dir;

    match git ["worktree"; "add"; temp_dir; ditz_branch] with
    | Error e -> Error e
    | Ok _ ->
      let result =
        match git ~cwd:temp_dir ["merge"; "origin/" ^ ditz_branch; "-m"; "ditz: merge remote changes"] with
        | Ok _ -> Ok ()
        | Error e ->
          (* TODO: implement conflict resolution *)
          Error e
      in
      let _ = git ["worktree"; "remove"; "--force"; temp_dir] in
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote temp_dir)) in
      result
  end

(** Push ditz-metadata to origin *)
let push () =
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
