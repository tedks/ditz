(** File storage for ditz - reads/writes YAML files from .ditz directory or git branch *)

open Types

(** Storage backend type *)
type backend =
  | Filesystem of string  (* path to .ditz directory *)
  | GitBranch             (* uses ditz-metadata branch via Git module *)

let default_issue_dir = ".ditz"

let config_file () =
  match Sys.getenv_opt "HOME" with
  | Some home -> Ok (Filename.concat home ".ditz-config")
  | None -> Error (`Msg "HOME not set; cannot locate config file")

let validate_id id =
  (* Allow alphanumeric, dashes, and underscores for human-readable IDs *)
  let is_valid_char = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' -> true
    | _ -> false
  in
  if id = "" then
    Error (`Msg "Invalid issue id: empty")
  else if String.for_all is_valid_char id then
    Ok id
  else
    Error (`Msg (Printf.sprintf "Invalid issue id '%s'" id))

(** Detect which backend to use *)
let detect_backend () =
  (* Check for git backend first (preferred) *)
  if Git.is_git_repo () && Git.ditz_metadata_exists () then
    GitBranch
  else if Sys.file_exists default_issue_dir && Sys.is_directory default_issue_dir then
    Filesystem default_issue_dir
  else
    (* No backend initialized yet *)
    Filesystem default_issue_dir

(** Parse YAML content into a value *)
let parse_yaml of_yaml content source =
  match Yaml.of_string content with
  | Ok yaml -> of_yaml yaml
  | Error (`Msg e) -> Error (`Msg (Printf.sprintf "YAML parse error in %s: %s" source e))

(** Serialize value to YAML string *)
let to_yaml_string to_yaml value =
  let yaml = to_yaml value in
  Yaml.to_string_exn yaml

(* Filesystem backend operations *)
module FS = struct
  let project_file dir = Filename.concat dir "project.yaml"

  let issue_files dir =
    Sys.readdir dir
    |> Array.to_list
    |> List.filter (fun f ->
        String.length f > 6 &&
        String.sub f 0 6 = "issue-" &&
        Filename.check_suffix f ".yaml")
    |> List.map (Filename.concat dir)

  let read_yaml_file of_yaml path =
    let ic = open_in path in
    let content = really_input_string ic (in_channel_length ic) in
    close_in ic;
    parse_yaml of_yaml content path

  (* Atomic write with temp file *)
  let write_yaml_file to_yaml path value =
    let content = to_yaml_string to_yaml value in
    let dir = Filename.dirname path in
    let base = Filename.basename path in
    let temp_path, oc = Filename.open_temp_file ~temp_dir:dir (base ^ ".tmp-") "" in
    try
      output_string oc content;
      close_out oc;
      Unix.rename temp_path path;
      Ok ()
    with exn ->
      close_out_noerr oc;
      (try Sys.remove temp_path with _ -> ());
      Error (`Msg (Printf.sprintf "Failed to write %s: %s" path (Printexc.to_string exn)))

  let load_project dir =
    read_yaml_file project_of_yaml (project_file dir)

  let save_project dir project =
    write_yaml_file project_to_yaml (project_file dir) project

  let load_issue path =
    read_yaml_file issue_of_yaml path

  let save_issue dir issue =
    match validate_id issue.id with
    | Error _ as e -> e
    | Ok safe_id ->
      let path = Filename.concat dir (Printf.sprintf "issue-%s.yaml" safe_id) in
      write_yaml_file issue_to_yaml path issue

  let load_issues dir =
    issue_files dir
    |> List.filter_map (fun path ->
        match load_issue path with
        | Ok issue -> Some issue
        | Error (`Msg e) ->
          Logs.warn (fun m -> m "Failed to load %s: %s" path e);
          None)

  let delete_issue dir id =
    match validate_id id with
    | Error _ as e -> e
    | Ok safe_id ->
      let path = Filename.concat dir (Printf.sprintf "issue-%s.yaml" safe_id) in
      if Sys.file_exists path then begin
        Sys.remove path;
        Ok ()
      end else
        Error (`Msg (Printf.sprintf "Issue %s not found" id))

  let init_project ~name ~issue_dir =
    if Sys.file_exists issue_dir then
      Error (`Msg (Printf.sprintf "Directory %s already exists" issue_dir))
    else begin
      Unix.mkdir issue_dir 0o755;
      let project = {
        name;
        version = "0.1.0";
        components = [{ name }];
        releases = [];
      } in
      save_project issue_dir project
    end

  let issue_path dir id =
    match validate_id id with
    | Error _ as e -> e
    | Ok safe_id -> Ok (Filename.concat dir (Printf.sprintf "issue-%s.yaml" safe_id))

  let find_issue_by_exact_id dir id =
    match issue_path dir id with
    | Error _ as e -> e
    | Ok path ->
      if Sys.file_exists path then
        load_issue path
      else
        Error (`Msg (Printf.sprintf "Issue %s not found" id))
end

(* Git backend operations *)
module GitBackend = struct
  let load_project () =
    match Git.read_file_from_branch ".ditz/project.yaml" with
    | Ok content -> parse_yaml project_of_yaml content ".ditz/project.yaml"
    | Error e -> Error e

  let save_project project =
    let content = to_yaml_string project_to_yaml project in
    Git.write_to_branch
      ~path:".ditz/project.yaml"
      ~content
      ~commit_msg:"ditz: update project"

  let load_issue filename =
    let path = ".ditz/" ^ filename in
    match Git.read_file_from_branch path with
    | Ok content -> parse_yaml issue_of_yaml content path
    | Error e -> Error e

  let save_issue issue ~commit_msg =
    match validate_id issue.id with
    | Error _ as e -> e
    | Ok safe_id ->
      let content = to_yaml_string issue_to_yaml issue in
      let path = Printf.sprintf ".ditz/issue-%s.yaml" safe_id in
      Git.write_to_branch ~path ~content ~commit_msg

  let load_issues () =
    let files = Git.list_ditz_files () in
    files
    |> List.filter (fun f ->
        let basename = Filename.basename f in
        String.length basename > 6 &&
        String.sub basename 0 6 = "issue-" &&
        Filename.check_suffix basename ".yaml")
    |> List.filter_map (fun path ->
        let filename = Filename.basename path in
        match load_issue filename with
        | Ok issue -> Some issue
        | Error (`Msg e) ->
          Logs.warn (fun m -> m "Failed to load %s: %s" path e);
          None)

  let delete_issue id ~commit_msg =
    match validate_id id with
    | Error _ as e -> e
    | Ok safe_id ->
      let path = Printf.sprintf ".ditz/issue-%s.yaml" safe_id in
      Git.delete_from_branch ~path ~commit_msg

  let init_project ~name =
    if Git.ditz_metadata_exists () then
      Error (`Msg "ditz-metadata branch already exists")
    else
      Git.create_ditz_metadata_branch ~project_name:name

  let find_issue_by_exact_id id =
    match validate_id id with
    | Error _ as e -> e
    | Ok safe_id ->
      let path = Printf.sprintf ".ditz/issue-%s.yaml" safe_id in
      match Git.read_file_from_branch path with
      | Ok content -> parse_yaml issue_of_yaml content path
      | Error _ -> Error (`Msg (Printf.sprintf "Issue %s not found" id))
end

(* Public API - dispatches to appropriate backend *)

(** Identity fallback when no config file exists:
    DITZ_USER/DITZ_EMAIL env vars take precedence (explicit beats inferred),
    then git config user.name/user.email. The two fields resolve
    independently, so DITZ_USER may pair with a git-config email — deliberate,
    so overriding one field doesn't force restating the other. *)
let identity_fallback () =
  let nonempty s = match String.trim s with "" -> None | t -> Some t in
  let from_git key =
    match Git.get_config key with
    | Ok v -> nonempty v
    | Error _ -> None
  in
  let lookup env_var git_key =
    match Option.bind (Sys.getenv_opt env_var) nonempty with
    | Some v -> Some v
    | None -> from_git git_key
  in
  match lookup "DITZ_USER" "user.name", lookup "DITZ_EMAIL" "user.email" with
  | Some name, Some email -> Ok { name; email; issue_dir = default_issue_dir }
  | _ ->
    Error (`Msg
      "No identity found. Set git config user.name and user.email, \
       or DITZ_USER and DITZ_EMAIL, or create ~/.ditz-config.")

let load_config () =
  match config_file () with
  | Ok path when Sys.file_exists path ->
    FS.read_yaml_file config_of_yaml path
  | Ok _ | Error _ ->
    (* No config file (or no HOME at all): fall back to git/env identity *)
    identity_fallback ()

let save_config config =
  match config_file () with
  | Error _ as e -> e
  | Ok path -> FS.write_yaml_file config_to_yaml path config

let load_project dir =
  match detect_backend () with
  | GitBranch -> GitBackend.load_project ()
  | Filesystem d -> FS.load_project (if dir = default_issue_dir then d else dir)

let save_project dir project =
  match detect_backend () with
  | GitBranch -> GitBackend.save_project project
  | Filesystem d -> FS.save_project (if dir = default_issue_dir then d else dir) project

let load_issues dir =
  match detect_backend () with
  | GitBranch -> GitBackend.load_issues ()
  | Filesystem d -> FS.load_issues (if dir = default_issue_dir then d else dir)

let save_issue ?(commit_msg = "ditz: update issue") dir issue =
  match detect_backend () with
  | GitBranch -> GitBackend.save_issue issue ~commit_msg
  | Filesystem d -> FS.save_issue (if dir = default_issue_dir then d else dir) issue

let delete_issue ?(commit_msg = "ditz: delete issue") dir id =
  match detect_backend () with
  | GitBranch -> GitBackend.delete_issue id ~commit_msg
  | Filesystem d -> FS.delete_issue (if dir = default_issue_dir then d else dir) id

let init_project ~name ~issue_dir =
  (* Prefer git backend if in a git repo *)
  if Git.is_git_repo () then
    GitBackend.init_project ~name
  else
    FS.init_project ~name ~issue_dir

let issue_path dir id =
  match validate_id id with
  | Error _ as e -> e
  | Ok safe_id -> Ok (Filename.concat dir (Printf.sprintf "issue-%s.yaml" safe_id))

let find_issue_by_id dir id_prefix =
  let issues = load_issues dir in
  let matches = List.filter (fun (issue : issue) ->
    String.length issue.id >= String.length id_prefix &&
    String.sub issue.id 0 (String.length id_prefix) = id_prefix
  ) issues in
  match matches with
  | [] -> Error (`Msg (Printf.sprintf "No issue found matching '%s'" id_prefix))
  | [issue] -> Ok issue
  | _ ->
    let ids = List.map (fun (i : issue) -> i.id) matches in
    Error (`Msg (Printf.sprintf "Ambiguous ID '%s' matches: %s" id_prefix (String.concat ", " ids)))

let find_issue_by_exact_id dir id =
  match detect_backend () with
  | GitBranch -> GitBackend.find_issue_by_exact_id id
  | Filesystem d -> FS.find_issue_by_exact_id (if dir = default_issue_dir then d else dir) id

(** Check which backend is currently active *)
let current_backend () = detect_backend ()

(** Check if using git backend *)
let is_git_backend () =
  match detect_backend () with
  | GitBranch -> true
  | Filesystem _ -> false
