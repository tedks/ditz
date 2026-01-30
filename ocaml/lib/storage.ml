(** File storage for ditz - reads/writes YAML files in .ditz directory *)

open Types

let default_issue_dir = ".ditz"

let project_file dir = Filename.concat dir "project.yaml"
let config_file () = Filename.concat (Sys.getenv "HOME") ".ditz-config"

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
  match to_yaml value with
  | Ok yaml ->
    let content = Yaml.to_string_exn yaml in
    let oc = open_out path in
    output_string oc content;
    close_out oc;
    Ok ()
  | Error e -> Error e

let load_project dir =
  read_yaml_file project_of_yaml (project_file dir)

let save_project dir project =
  write_yaml_file project_to_yaml (project_file dir) project

let load_issue path =
  read_yaml_file issue_of_yaml path

let save_issue dir issue =
  let path = Filename.concat dir (Printf.sprintf "issue-%s.yaml" issue.id) in
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
  let path = config_file () in
  if Sys.file_exists path then
    read_yaml_file config_of_yaml path
  else
    Error (`Msg "No config found. Run 'ditz init' first.")

let save_config config =
  write_yaml_file config_to_yaml (config_file ()) config

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
  Filename.concat dir (Printf.sprintf "issue-%s.yaml" id)

let delete_issue dir id =
  let path = issue_path dir id in
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
