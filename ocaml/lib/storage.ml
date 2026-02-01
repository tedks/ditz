(** File storage for ditz - reads/writes YAML files in .ditz directory *)

open Types

let default_issue_dir = ".ditz"

let project_file dir = Filename.concat dir "project.yaml"
let config_file () =
  match Sys.getenv_opt "HOME" with
  | Some home -> Ok (Filename.concat home ".ditz-config")
  | None -> Error (`Msg "HOME not set; cannot locate config file")

let validate_id id =
  let is_alnum = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> true
    | _ -> false
  in
  if id = "" then
    Error (`Msg "Invalid issue id: empty")
  else if String.for_all is_alnum id then
    Ok id
  else
    Error (`Msg (Printf.sprintf "Invalid issue id '%s'" id))

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
  match Yaml.of_string content with
  | Ok yaml -> of_yaml yaml
  | Error (`Msg e) -> Error (`Msg (Printf.sprintf "YAML parse error in %s: %s" path e))

let write_yaml_file to_yaml path value =
  let yaml = to_yaml value in
  let content = Yaml.to_string_exn yaml in
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

let load_config () =
  match config_file () with
  | Error _ as e -> e
  | Ok path ->
    if Sys.file_exists path then
      read_yaml_file config_of_yaml path
    else
      Error (`Msg "No config found. Run 'ditz init' first.")

let save_config config =
  match config_file () with
  | Error _ as e -> e
  | Ok path -> write_yaml_file config_to_yaml path config

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

let delete_issue dir id =
  match issue_path dir id with
  | Error _ as e -> e
  | Ok path ->
    if Sys.file_exists path then begin
      Sys.remove path;
      Ok ()
    end else
      Error (`Msg (Printf.sprintf "Issue %s not found" id))

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
