(** ditz - distributed issue tracker *)

open Cmdliner

let setup_log style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter (Logs_fmt.reporter ());
  ()

let setup_log_term =
  Term.(const setup_log $ Fmt_cli.style_renderer () $ Logs_cli.level ())

(* Commands *)

let list_cmd =
  let doc = "List issues" in
  let info = Cmd.info "list" ~doc in
  let run () =
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let issues = Ditz.Storage.load_issues config.issue_dir in
      List.iter (fun (issue : Ditz.Types.issue) ->
        let widget = Ditz.Types.status_widget issue.status in
        Fmt.pr "[%s] %s: %s@." widget issue.id issue.title
      ) issues;
      0
  in
  Cmd.v info Term.(const run $ setup_log_term)

let add_cmd =
  let doc = "Add a new issue" in
  let info = Cmd.info "add" ~doc in
  let title_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"TITLE") in
  let run title () =
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let id = Ditz.Types.make_id ~title ~desc:"" ~reporter:config.name in
      let now =
        match Ptime.of_float_s (Unix.gettimeofday ()) with
        | Some t -> Ptime.to_rfc3339 t
        | None -> "1970-01-01T00:00:00Z"
      in
      let issue : Ditz.Types.issue = {
        id;
        title;
        desc = "";
        issue_type = Ditz.Types.Task;
        component = "default";
        release = None;
        reporter = Printf.sprintf "%s <%s>" config.name config.email;
        status = Ditz.Types.Unstarted;
        disposition = None;
        creation_time = now;
        references = [];
        log_events = [{
          time = now;
          who = config.name;
          what = "created";
          comment = "";
        }];
      } in
      match Ditz.Storage.save_issue config.issue_dir issue with
      | Ok () ->
        Fmt.pr "Created issue %s@." id; 0
      | Error (`Msg e) ->
        Fmt.epr "Error: %s@." e; 1
  in
  Cmd.v info Term.(const run $ title_arg $ setup_log_term)

let init_cmd =
  let doc = "Initialize a new ditz project" in
  let info = Cmd.info "init" ~doc in
  let run () =
    let name = Filename.basename (Sys.getcwd ()) in
    match Ditz.Storage.init_project ~name ~issue_dir:".ditz" with
    | Ok () ->
      Fmt.pr "Initialized ditz project '%s'@." name; 0
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
  in
  Cmd.v info Term.(const run $ setup_log_term)

let main_cmd =
  let doc = "Distributed issue tracker" in
  let info = Cmd.info "ditz" ~version:"0.1.0-ocaml" ~doc in
  Cmd.group info [list_cmd; add_cmd; init_cmd]

let () = exit (Cmd.eval main_cmd)
