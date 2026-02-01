(** ditz - distributed issue tracker *)

open Cmdliner

(* Output mode type *)
type output_mode = Human | Json | Quiet

let setup_log style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter (Logs_fmt.reporter ());
  ()

let setup_log_term =
  Term.(const setup_log $ Fmt_cli.style_renderer () $ Logs_cli.level ())

(* Common flags for output mode *)
let json_flag = Arg.(value & flag & info ["json"] ~doc:"Output in JSON format")
let quiet_flag = Arg.(value & flag & info ["ids-only"] ~doc:"Output only issue IDs (one per line)")

let output_mode json quiet =
  if json then Json
  else if quiet then Quiet
  else Human

(* String set for efficient membership testing *)
module StringSet = Set.Make(String)

(* Commands *)

let list_cmd =
  let doc = "List issues" in
  let info = Cmd.info "list" ~doc in
  let run json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let issues = Ditz.Storage.load_issues config.issue_dir in
      (match mode with
       | Json ->
         Fmt.pr "%s@." (Ditz.Types.issues_to_json issues)
       | Quiet ->
         List.iter (fun (issue : Ditz.Types.issue) ->
           Fmt.pr "%s@." issue.id
         ) issues
       | Human ->
         List.iter (fun (issue : Ditz.Types.issue) ->
           let widget = Ditz.Types.status_widget issue.status in
           Fmt.pr "[%s] %s: %s@." widget issue.id issue.title
         ) issues);
      0
  in
  Cmd.v info Term.(const run $ json_flag $ quiet_flag $ setup_log_term)

let add_cmd =
  let doc = "Add a new issue" in
  let info = Cmd.info "add" ~doc in
  let title_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"TITLE") in
  let run title json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let id = Ditz.Types.make_id ~title ~desc:"" ~reporter:config.name in
      let now = Ditz.Issue_ops.now_rfc3339 () in
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
      match Ditz.Storage.save_issue config.issue_dir issue with
      | Ok () ->
        (match mode with
         | Json -> Fmt.pr "%s@." (Ditz.Types.simple_issue_json issue)
         | Quiet -> Fmt.pr "%s@." id
         | Human -> Fmt.pr "Created issue %s@." id);
        0
      | Error (`Msg e) ->
        Fmt.epr "Error: %s@." e; 1
  in
  Cmd.v info Term.(const run $ title_arg $ json_flag $ quiet_flag $ setup_log_term)

let init_cmd =
  let doc = "Initialize a new ditz project" in
  let info = Cmd.info "init" ~doc in
  let run json quiet () =
    let mode = output_mode json quiet in
    let name = Filename.basename (Sys.getcwd ()) in
    match Ditz.Storage.init_project ~name ~issue_dir:".ditz" with
    | Ok () ->
      (match mode with
       | Json -> Fmt.pr {|{"project":"%s","status":"initialized"}@.|} (Ditz.Types.escape_json_string name)
       | Quiet -> Fmt.pr "%s@." name
       | Human -> Fmt.pr "Initialized ditz project '%s'@." name);
      0
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
  in
  Cmd.v info Term.(const run $ json_flag $ quiet_flag $ setup_log_term)

let show_cmd =
  let doc = "Show issue details" in
  let info = Cmd.info "show" ~doc in
  let id_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Issue ID (or prefix)") in
  let run id json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      match Ditz.Storage.find_issue_by_id config.issue_dir id with
      | Error (`Msg e) ->
        Fmt.epr "Error: %s@." e; 1
      | Ok issue ->
        (match mode with
         | Json ->
           Fmt.pr "%s@." (Ditz.Types.issue_to_json issue)
         | Quiet ->
           Fmt.pr "%s@." issue.id
         | Human ->
           Fmt.pr "@[<v>";
           Fmt.pr "Issue: %s@," issue.id;
           Fmt.pr "Title: %s@," issue.title;
           Fmt.pr "Type: %s@," (Ditz.Types.issue_type_to_string issue.issue_type);
           Fmt.pr "Status: %s@," (Ditz.Types.status_to_string issue.status);
           (match issue.disposition with
            | Some d -> Fmt.pr "Disposition: %s@," (Ditz.Types.disposition_to_string d)
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
           Fmt.pr "@]");
        0
  in
  Cmd.v info Term.(const run $ id_arg $ json_flag $ quiet_flag $ setup_log_term)

let close_cmd =
  let doc = "Close one or more issues" in
  let info = Cmd.info "close" ~doc in
  let ids_arg = Arg.(non_empty & pos_all string [] & info [] ~docv:"ID" ~doc:"Issue ID(s) (or prefix)") in
  let fixed_flag = Arg.(value & flag & info ["fixed"] ~doc:"Close as fixed") in
  let wontfix_flag = Arg.(value & flag & info ["wontfix"] ~doc:"Close as won't fix") in
  let reorg_flag = Arg.(value & flag & info ["reorg"] ~doc:"Close due to reorganization") in
  let run ids fixed wontfix reorg json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let disposition =
        match (fixed, wontfix, reorg) with
        | (true, false, false) -> Some Ditz.Types.Fixed
        | (false, true, false) -> Some Ditz.Types.Wontfix
        | (false, false, true) -> Some Ditz.Types.Reorg
        | (false, false, false) -> Some Ditz.Types.Fixed  (* default *)
        | _ -> None
      in
      match disposition with
      | None ->
        Fmt.epr "Error: specify at most one of --fixed, --wontfix, --reorg@."; 1
      | Some disp ->
        let disp_str = Ditz.Types.disposition_to_string disp in
        (* Use fold_left instead of mutable refs *)
        let (closed_ids, errors) = List.fold_left (fun (ok, err) id ->
          match Ditz.Storage.find_issue_by_id config.issue_dir id with
          | Error (`Msg e) -> (ok, (id, e) :: err)
          | Ok issue ->
            let issue = Ditz.Issue_ops.close_issue issue ~who:config.name ~disposition:disp in
            match Ditz.Storage.save_issue config.issue_dir issue with
            | Ok () -> (issue.id :: ok, err)
            | Error (`Msg e) -> (ok, (id, e) :: err)
        ) ([], []) ids in
        let closed_ids = List.rev closed_ids in
        let errors = List.rev errors in
        (* Output results *)
        (match mode with
         | Json ->
           let closed_json = String.concat "," (List.map (fun id ->
             Printf.sprintf {|"%s"|} (Ditz.Types.escape_json_string id)
           ) closed_ids) in
           let errors_json = String.concat "," (List.map (fun (id, e) ->
             Printf.sprintf {|{"id":"%s","error":"%s"}|}
               (Ditz.Types.escape_json_string id)
               (Ditz.Types.escape_json_string e)
           ) errors) in
           Fmt.pr {|{"closed":[%s],"errors":[%s],"disposition":"%s"}@.|} closed_json errors_json disp_str
         | Quiet ->
           List.iter (fun id -> Fmt.pr "%s@." id) closed_ids
         | Human ->
           List.iter (fun id -> Fmt.pr "Closed issue %s (%s)@." id disp_str) closed_ids;
           List.iter (fun (id, e) -> Fmt.epr "Error closing %s: %s@." id e) errors);
        if errors = [] then 0 else 1
  in
  Cmd.v info Term.(const run $ ids_arg $ fixed_flag $ wontfix_flag $ reorg_flag $ json_flag $ quiet_flag $ setup_log_term)

let start_cmd =
  let doc = "Start working on one or more issues" in
  let info = Cmd.info "start" ~doc in
  let ids_arg = Arg.(non_empty & pos_all string [] & info [] ~docv:"ID" ~doc:"Issue ID(s) (or prefix)") in
  let run ids json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let (started, errors) = List.fold_left (fun (ok, err) id ->
        match Ditz.Storage.find_issue_by_id config.issue_dir id with
        | Error (`Msg e) -> (ok, (id, e) :: err)
        | Ok issue ->
          match Ditz.Issue_ops.start_issue issue ~who:config.name with
          | Error (`Msg e) -> (ok, (id, e) :: err)
          | Ok issue ->
            match Ditz.Storage.save_issue config.issue_dir issue with
            | Ok () -> (issue :: ok, err)
            | Error (`Msg e) -> (ok, (id, e) :: err)
      ) ([], []) ids in
      let started = List.rev started in
      let errors = List.rev errors in
      (match mode with
       | Json ->
         let started_json = String.concat "," (List.map Ditz.Types.simple_issue_json started) in
         let errors_json = String.concat "," (List.map (fun (id, e) ->
           Printf.sprintf {|{"id":"%s","error":"%s"}|}
             (Ditz.Types.escape_json_string id)
             (Ditz.Types.escape_json_string e)
         ) errors) in
         Fmt.pr {|{"started":[%s],"errors":[%s]}@.|} started_json errors_json
       | Quiet ->
         List.iter (fun (i : Ditz.Types.issue) -> Fmt.pr "%s@." i.id) started
       | Human ->
         List.iter (fun (i : Ditz.Types.issue) -> Fmt.pr "Started issue %s@." i.id) started;
         List.iter (fun (id, e) -> Fmt.epr "Error starting %s: %s@." id e) errors);
      if errors = [] then 0 else 1
  in
  Cmd.v info Term.(const run $ ids_arg $ json_flag $ quiet_flag $ setup_log_term)

let stop_cmd =
  let doc = "Stop working on one or more issues (pause)" in
  let info = Cmd.info "stop" ~doc in
  let ids_arg = Arg.(non_empty & pos_all string [] & info [] ~docv:"ID" ~doc:"Issue ID(s) (or prefix)") in
  let run ids json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let (stopped, errors) = List.fold_left (fun (ok, err) id ->
        match Ditz.Storage.find_issue_by_id config.issue_dir id with
        | Error (`Msg e) -> (ok, (id, e) :: err)
        | Ok issue ->
          match Ditz.Issue_ops.stop_issue issue ~who:config.name with
          | Error (`Msg e) -> (ok, (id, e) :: err)
          | Ok issue ->
            match Ditz.Storage.save_issue config.issue_dir issue with
            | Ok () -> (issue :: ok, err)
            | Error (`Msg e) -> (ok, (id, e) :: err)
      ) ([], []) ids in
      let stopped = List.rev stopped in
      let errors = List.rev errors in
      (match mode with
       | Json ->
         let stopped_json = String.concat "," (List.map Ditz.Types.simple_issue_json stopped) in
         let errors_json = String.concat "," (List.map (fun (id, e) ->
           Printf.sprintf {|{"id":"%s","error":"%s"}|}
             (Ditz.Types.escape_json_string id)
             (Ditz.Types.escape_json_string e)
         ) errors) in
         Fmt.pr {|{"stopped":[%s],"errors":[%s]}@.|} stopped_json errors_json
       | Quiet ->
         List.iter (fun (i : Ditz.Types.issue) -> Fmt.pr "%s@." i.id) stopped
       | Human ->
         List.iter (fun (i : Ditz.Types.issue) -> Fmt.pr "Stopped issue %s@." i.id) stopped;
         List.iter (fun (id, e) -> Fmt.epr "Error stopping %s: %s@." id e) errors);
      if errors = [] then 0 else 1
  in
  Cmd.v info Term.(const run $ ids_arg $ json_flag $ quiet_flag $ setup_log_term)

let drop_cmd =
  let doc = "Delete an issue" in
  let info = Cmd.info "drop" ~doc in
  let id_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Issue ID (or prefix)") in
  let run id json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      match Ditz.Storage.find_issue_by_id config.issue_dir id with
      | Error (`Msg e) ->
        Fmt.epr "Error: %s@." e; 1
      | Ok issue ->
        match Ditz.Storage.delete_issue config.issue_dir issue.id with
        | Ok () ->
          (match mode with
           | Json -> Fmt.pr {|{"deleted":"%s"}@.|} (Ditz.Types.escape_json_string issue.id)
           | Quiet -> Fmt.pr "%s@." issue.id
           | Human -> Fmt.pr "Deleted issue %s@." issue.id);
          0
        | Error (`Msg e) ->
          Fmt.epr "Error: %s@." e; 1
  in
  Cmd.v info Term.(const run $ id_arg $ json_flag $ quiet_flag $ setup_log_term)

(* Context command - dump all open issues for LLM context *)
let context_cmd =
  let doc = "Dump all open issues (optimized for LLM context)" in
  let info = Cmd.info "context" ~doc in
  let issue_arg = Arg.(value & opt (some string) None & info ["issue"; "i"] ~docv:"ID" ~doc:"Focus on specific issue and related issues") in
  let run issue_id json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let all_issues = Ditz.Storage.load_issues config.issue_dir in
      let open_issues = List.filter (fun (i : Ditz.Types.issue) ->
        i.status <> Ditz.Types.Closed
      ) all_issues in
      let issues_result = match issue_id with
        | None -> Ok open_issues
        | Some id ->
          (* Focus on a specific issue and its related issues *)
          match Ditz.Storage.find_issue_by_id config.issue_dir id with
          | Error e -> Error e
          | Ok focus ->
            let related_ids = focus.blocks @ focus.blocked_by in
            let related = List.filter (fun (i : Ditz.Types.issue) ->
              List.mem i.id related_ids
            ) all_issues in
            Ok (focus :: related)
      in
      match issues_result with
      | Error (`Msg e) ->
        Fmt.epr "Error: %s@." e; 1
      | Ok issues ->
        (match mode with
         | Json ->
           Fmt.pr "%s@." (Ditz.Types.issues_to_json issues)
         | Quiet ->
           List.iter (fun (i : Ditz.Types.issue) -> Fmt.pr "%s@." i.id) issues
         | Human ->
           Fmt.pr "# Open Issues (%d)@.@." (List.length issues);
           List.iter (fun (issue : Ditz.Types.issue) ->
             let widget = Ditz.Types.status_widget issue.status in
             Fmt.pr "## [%s] %s@." widget issue.id;
             Fmt.pr "**%s**@." issue.title;
             Fmt.pr "Type: %s | Component: %s@."
               (Ditz.Types.issue_type_to_string issue.issue_type)
               issue.component;
             if issue.desc <> "" then
               Fmt.pr "@.%s@." issue.desc;
             if issue.blocks <> [] then
               Fmt.pr "@.Blocks: %s@." (String.concat ", " issue.blocks);
             if issue.blocked_by <> [] then
               Fmt.pr "Blocked by: %s@." (String.concat ", " issue.blocked_by);
             if issue.file_refs <> [] then begin
               Fmt.pr "@.Files:@.";
               List.iter (fun (ref : Ditz.Types.file_ref) ->
                 let loc = match ref.line with
                   | Some l -> Printf.sprintf "%s:%d" ref.path l
                   | None -> ref.path
                 in
                 Fmt.pr "  - %s@." loc
               ) issue.file_refs
             end;
             Fmt.pr "@."
           ) issues);
        0
  in
  Cmd.v info Term.(const run $ issue_arg $ json_flag $ quiet_flag $ setup_log_term)

(* Ready command - show issues that can be worked on now *)
let ready_cmd =
  let doc = "Show issues ready to work on (unstarted/paused, not blocked)" in
  let info = Cmd.info "ready" ~doc in
  let run json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let all_issues = Ditz.Storage.load_issues config.issue_dir in
      (* Use Set for O(1) membership testing *)
      let open_ids = List.fold_left (fun acc (i : Ditz.Types.issue) ->
        if i.status <> Ditz.Types.Closed then StringSet.add i.id acc else acc
      ) StringSet.empty all_issues in
      (* Find ready issues: unstarted or paused, not blocked by any open issue *)
      let ready_issues = List.filter (fun (issue : Ditz.Types.issue) ->
        (issue.status = Ditz.Types.Unstarted || issue.status = Ditz.Types.Paused) &&
        (* Not blocked by any open issue *)
        not (List.exists (fun blocked_by_id ->
          StringSet.mem blocked_by_id open_ids
        ) issue.blocked_by)
      ) all_issues in
      (match mode with
       | Json ->
         Fmt.pr "%s@." (Ditz.Types.issues_to_json ready_issues)
       | Quiet ->
         List.iter (fun (i : Ditz.Types.issue) -> Fmt.pr "%s@." i.id) ready_issues
       | Human ->
         if ready_issues = [] then
           Fmt.pr "No issues ready to work on.@."
         else begin
           Fmt.pr "Ready to work on (%d issues):@.@." (List.length ready_issues);
           List.iter (fun (issue : Ditz.Types.issue) ->
             let widget = Ditz.Types.status_widget issue.status in
             Fmt.pr "[%s] %s: %s@." widget issue.id issue.title
           ) ready_issues
         end);
      0
  in
  Cmd.v info Term.(const run $ json_flag $ quiet_flag $ setup_log_term)

let main_cmd =
  let doc = "Distributed issue tracker" in
  let info = Cmd.info "ditz" ~version:"0.1.0-ocaml" ~doc in
  Cmd.group info [
    list_cmd;
    add_cmd;
    init_cmd;
    show_cmd;
    close_cmd;
    start_cmd;
    stop_cmd;
    drop_cmd;
    context_cmd;
    ready_cmd;
  ]

let () = exit (Cmd.eval' main_cmd)
