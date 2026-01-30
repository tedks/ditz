(** ditz - distributed issue tracker *)

open Cmdliner

let setup_log style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter (Logs_fmt.reporter ());
  ()

let setup_log_term =
  Term.(const setup_log $ Fmt_cli.style_renderer () $ Logs_cli.level ())

(* Helper to exit on error *)
let or_die = function
  | Ok x -> x
  | Error (`Msg e) ->
    Fmt.epr "Error: %s@." e;
    exit 1

(* Helper to get current timestamp *)
let now_rfc3339 () =
  match Ptime.of_float_s (Unix.gettimeofday ()) with
  | Some t -> Ptime.to_rfc3339 t
  | None -> "1970-01-01T00:00:00Z"

(* Helper to add a log event to an issue *)
let add_log_event (issue : Ditz.Types.issue) ~who ~what ~comment : Ditz.Types.issue =
  let event : Ditz.Types.log_event = {
    time = now_rfc3339 ();
    who;
    what;
    comment;
  } in
  { issue with log_events = issue.log_events @ [event] }

(* Commands *)

let list_cmd =
  let doc = "List issues" in
  let info = Cmd.info "list" ~doc in
  let run () =
    let config = or_die (Ditz.Storage.load_config ()) in
    let issues = Ditz.Storage.load_issues config.issue_dir in
    List.iter (fun (issue : Ditz.Types.issue) ->
      let widget = Ditz.Types.status_widget issue.status in
      Fmt.pr "[%s] %s: %s@." widget issue.id issue.title
    ) issues
  in
  Cmd.v info Term.(const run $ setup_log_term)

let add_cmd =
  let doc = "Add a new issue" in
  let info = Cmd.info "add" ~doc in
  let title_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"TITLE") in
  let run title () =
    let config = or_die (Ditz.Storage.load_config ()) in
    let id = Ditz.Types.make_id ~title ~desc:"" ~reporter:config.name in
    let now = now_rfc3339 () in
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
      blocks = [];
      blocked_by = [];
      file_refs = [];
    } in
    or_die (Ditz.Storage.save_issue config.issue_dir issue);
    Fmt.pr "Created issue %s@." id
  in
  Cmd.v info Term.(const run $ title_arg $ setup_log_term)

let init_cmd =
  let doc = "Initialize a new ditz project" in
  let info = Cmd.info "init" ~doc in
  let run () =
    let name = Filename.basename (Sys.getcwd ()) in
    or_die (Ditz.Storage.init_project ~name ~issue_dir:".ditz");
    Fmt.pr "Initialized ditz project '%s'@." name
  in
  Cmd.v info Term.(const run $ setup_log_term)

let show_cmd =
  let doc = "Show issue details" in
  let info = Cmd.info "show" ~doc in
  let id_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Issue ID (or prefix)") in
  let run id () =
    let config = or_die (Ditz.Storage.load_config ()) in
    let issue = or_die (Ditz.Storage.find_issue_by_id config.issue_dir id) in
    Fmt.pr "@[<v>";
    Fmt.pr "Issue: %s@," issue.id;
    Fmt.pr "Title: %s@," issue.title;
    Fmt.pr "Type: %s@," (Ditz.Types.issue_type_to_string issue.issue_type);
    Fmt.pr "Status: %s@," (Ditz.Types.status_to_string issue.status);
    (match issue.disposition with
     | Some d ->
       Fmt.pr "Disposition: %s@," (Ditz.Types.disposition_to_string d)
     | None -> ());
    Fmt.pr "Component: %s@," issue.component;
    (match issue.release with
     | Some r -> Fmt.pr "Release: %s@," r
     | None -> ());
    Fmt.pr "Reporter: %s@," issue.reporter;
    Fmt.pr "Created: %s@," issue.creation_time;
    if issue.desc <> "" then
      Fmt.pr "@,Description:@,  %s@," issue.desc;
    if issue.blocks <> [] then
      Fmt.pr "@,Blocks: %s@," (String.concat ", " issue.blocks);
    if issue.blocked_by <> [] then
      Fmt.pr "@,Blocked by: %s@," (String.concat ", " issue.blocked_by);
    if issue.file_refs <> [] then begin
      Fmt.pr "@,File references:@,";
      List.iter (fun (ref : Ditz.Types.file_ref) ->
        let loc = match ref.line with
          | Some l -> Printf.sprintf "%s:%d" ref.path l
          | None -> ref.path
        in
        match ref.note with
        | Some n -> Fmt.pr "  - %s (%s)@," loc n
        | None -> Fmt.pr "  - %s@," loc
      ) issue.file_refs
    end;
    if issue.log_events <> [] then begin
      Fmt.pr "@,Log:@,";
      List.iter (fun (ev : Ditz.Types.log_event) ->
        Fmt.pr "  [%s] %s: %s" ev.time ev.who ev.what;
        if ev.comment <> "" then
          Fmt.pr "@,    %s" ev.comment;
        Fmt.pr "@,"
      ) issue.log_events
    end;
    Fmt.pr "@]"
  in
  Cmd.v info Term.(const run $ id_arg $ setup_log_term)

let close_cmd =
  let doc = "Close an issue" in
  let info = Cmd.info "close" ~doc in
  let id_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Issue ID (or prefix)") in
  let fixed_flag = Arg.(value & flag & info ["fixed"] ~doc:"Close as fixed") in
  let wontfix_flag = Arg.(value & flag & info ["wontfix"] ~doc:"Close as won't fix") in
  let reorg_flag = Arg.(value & flag & info ["reorg"] ~doc:"Close due to reorganization") in
  let run id fixed wontfix reorg () =
    let config = or_die (Ditz.Storage.load_config ()) in
    let issue = or_die (Ditz.Storage.find_issue_by_id config.issue_dir id) in
    let disposition =
      match (fixed, wontfix, reorg) with
      | (true, false, false) -> Ditz.Types.Fixed
      | (false, true, false) -> Ditz.Types.Wontfix
      | (false, false, true) -> Ditz.Types.Reorg
      | (false, false, false) -> Ditz.Types.Fixed  (* default *)
      | _ ->
        Fmt.epr "Error: specify at most one of --fixed, --wontfix, --reorg@.";
        exit 1
    in
    let disp_str = Ditz.Types.disposition_to_string disposition in
    let issue = { issue with
      status = Ditz.Types.Closed;
      disposition = Some disposition;
    } in
    let issue = add_log_event issue ~who:config.name ~what:("closed: " ^ disp_str) ~comment:"" in
    or_die (Ditz.Storage.save_issue config.issue_dir issue);
    Fmt.pr "Closed issue %s (%s)@." issue.id disp_str
  in
  Cmd.v info Term.(const run $ id_arg $ fixed_flag $ wontfix_flag $ reorg_flag $ setup_log_term)

let start_cmd =
  let doc = "Start working on an issue" in
  let info = Cmd.info "start" ~doc in
  let id_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Issue ID (or prefix)") in
  let run id () =
    let config = or_die (Ditz.Storage.load_config ()) in
    let issue = or_die (Ditz.Storage.find_issue_by_id config.issue_dir id) in
    if issue.status = Ditz.Types.Closed then begin
      Fmt.epr "Error: issue %s is closed@." issue.id;
      exit 1
    end;
    let issue = { issue with status = Ditz.Types.In_progress } in
    let issue = add_log_event issue ~who:config.name ~what:"started" ~comment:"" in
    or_die (Ditz.Storage.save_issue config.issue_dir issue);
    Fmt.pr "Started issue %s@." issue.id
  in
  Cmd.v info Term.(const run $ id_arg $ setup_log_term)

let stop_cmd =
  let doc = "Stop working on an issue (pause)" in
  let info = Cmd.info "stop" ~doc in
  let id_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Issue ID (or prefix)") in
  let run id () =
    let config = or_die (Ditz.Storage.load_config ()) in
    let issue = or_die (Ditz.Storage.find_issue_by_id config.issue_dir id) in
    if issue.status = Ditz.Types.Closed then begin
      Fmt.epr "Error: issue %s is closed@." issue.id;
      exit 1
    end;
    let issue = { issue with status = Ditz.Types.Paused } in
    let issue = add_log_event issue ~who:config.name ~what:"stopped" ~comment:"" in
    or_die (Ditz.Storage.save_issue config.issue_dir issue);
    Fmt.pr "Stopped issue %s@." issue.id
  in
  Cmd.v info Term.(const run $ id_arg $ setup_log_term)

let drop_cmd =
  let doc = "Delete an issue" in
  let info = Cmd.info "drop" ~doc in
  let id_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Issue ID (or prefix)") in
  let run id () =
    let config = or_die (Ditz.Storage.load_config ()) in
    (* First find the issue to get its full ID *)
    let issue = or_die (Ditz.Storage.find_issue_by_id config.issue_dir id) in
    or_die (Ditz.Storage.delete_issue config.issue_dir issue.id);
    Fmt.pr "Deleted issue %s@." issue.id
  in
  Cmd.v info Term.(const run $ id_arg $ setup_log_term)

let main_cmd =
  let doc = "Distributed issue tracker" in
  let info = Cmd.info "ditz" ~version:"0.1.0-ocaml" ~doc in
  Cmd.group info [list_cmd; add_cmd; init_cmd; show_cmd; close_cmd; start_cmd; stop_cmd; drop_cmd]

let () = exit (Cmd.eval main_cmd)
