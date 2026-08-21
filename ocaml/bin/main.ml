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
(* Quiet/ids-only output. NB: cannot alias to "-q" — that short flag is taken
   by cmdliner's log-verbosity option (setup_log_term). --ids-only it is; the
   onboarding doc teaches this rather than the beads -q muscle memory. *)
let quiet_flag = Arg.(value & flag & info ["ids-only"] ~doc:"Output only issue IDs (one per line)")

let output_mode json quiet =
  if json then Json
  else if quiet then Quiet
  else Human

(* String set for efficient membership testing *)
module StringSet = Set.Make(String)

(* Commands *)

let issue_type_of_string s =
  match String.lowercase_ascii s with
  | "bug" | "bugfix" -> Some Ditz.Types.Bugfix
  | "feature" -> Some Ditz.Types.Feature
  | "task" -> Some Ditz.Types.Task
  | _ -> None

let status_of_string s =
  match String.lowercase_ascii s with
  | "unstarted" -> Some Ditz.Types.Unstarted
  | "in_progress" | "inprogress" | "started" -> Some Ditz.Types.In_progress
  | "paused" | "stopped" -> Some Ditz.Types.Paused
  | "closed" -> Some Ditz.Types.Closed
  | _ -> None

let list_cmd =
  let doc = "List issues" in
  let info = Cmd.info "list" ~doc in
  let type_opt = Arg.(value & opt (some string) None & info ["type"; "t"] ~docv:"TYPE" ~doc:"Filter by type (bug, feature, task)") in
  let component_opt = Arg.(value & opt (some string) None & info ["component"; "c"] ~docv:"COMPONENT" ~doc:"Filter by component") in
  let status_opt = Arg.(value & opt (some string) None & info ["status"; "s"] ~docv:"STATUS" ~doc:"Filter by status (unstarted, in_progress, paused, closed)") in
  let run type_filter component_filter status_filter json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let issues = Ditz.Storage.load_issues config.issue_dir in
      (* Apply filters *)
      let issues = match type_filter with
        | None -> issues
        | Some t ->
          match issue_type_of_string t with
          | None -> Fmt.epr "Warning: unknown type '%s'@." t; issues
          | Some typ -> List.filter (fun (i : Ditz.Types.issue) -> i.issue_type = typ) issues
      in
      let issues = match component_filter with
        | None -> issues
        | Some c -> List.filter (fun (i : Ditz.Types.issue) -> i.component = c) issues
      in
      let issues = match status_filter with
        | None -> issues
        | Some s ->
          match status_of_string s with
          | None -> Fmt.epr "Warning: unknown status '%s'@." s; issues
          | Some st -> List.filter (fun (i : Ditz.Types.issue) -> i.status = st) issues
      in
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
  Cmd.v info Term.(const run $ type_opt $ component_opt $ status_opt $ json_flag $ quiet_flag $ setup_log_term)

let read_stdin () =
  let buf = Buffer.create 256 in
  try
    while true do
      Buffer.add_channel buf stdin 1024
    done;
    Buffer.contents buf
  with End_of_file ->
    Buffer.contents buf |> String.trim

let add_cmd =
  let doc = "Add a new issue" in
  let info = Cmd.info "add" ~doc in
  let title_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"TITLE") in
  let id_opt = Arg.(value & opt (some string) None & info ["id"] ~docv:"ID" ~doc:"Use specific ID (idempotent - returns existing issue if ID exists)") in
  let type_opt = Arg.(value & opt (some string) None & info ["type"; "t"] ~docv:"TYPE" ~doc:"Issue type (bugfix, feature, task; default task)") in
  let component_opt = Arg.(value & opt (some string) None & info ["component"; "c"] ~docv:"COMPONENT" ~doc:"Component (default \"default\")") in
  let desc_opt = Arg.(value & opt (some string) None & info ["desc"; "d"] ~docv:"DESC" ~doc:"Description") in
  let desc_stdin_flag = Arg.(value & flag & info ["desc-stdin"] ~doc:"Read description from stdin") in
  let run title custom_id type_str component desc desc_stdin json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      (* Idempotent fast path FIRST: with an explicit --id, an existing issue
         is returned unchanged. This must precede creation-only validation
         (--type) and any stdin read, so a no-op re-add never fails on a bad
         creation flag or blocks on stdin. *)
      let existing = match custom_id with
        | Some id ->
          (match Ditz.Storage.find_issue_by_exact_id config.issue_dir id with
           | Ok e -> Some e | Error _ -> None)
        | None -> None
      in
      match existing with
      | Some existing ->
        (match mode with
         | Json -> Fmt.pr "%s@." (Ditz.Types.simple_issue_json existing)
         | Quiet -> Fmt.pr "%s@." existing.id
         | Human -> Fmt.pr "Issue %s already exists@." existing.id);
        0
      | None ->
        (* Creating: now resolve description and validate creation-only fields. *)
        let desc = match (desc, desc_stdin) with
          | (Some d, false) -> d
          | (None, true) -> read_stdin ()
          | (Some d, true) -> Fmt.epr "Warning: ignoring --desc-stdin since --desc provided@."; d
          | (None, false) -> ""
        in
        let issue_type_result = match type_str with
          | None -> Ok Ditz.Types.Task
          | Some t ->
            (match issue_type_of_string t with
             | Some ty -> Ok ty
             | None -> Error (Printf.sprintf "unknown type '%s' (use bugfix, feature, task)" t))
        in
        match issue_type_result with
        | Error e -> Fmt.epr "Error: %s@." e; 1
        | Ok issue_type ->
          let component = Option.value component ~default:"default" in
          let id = match custom_id with
            | Some id -> id
            | None -> Ditz.Types.make_id ~title ~desc ~reporter:config.name
          in
          let issue = Ditz.Issue_ops.new_issue ~id ~title ~desc ~issue_type ~component
            ~reporter:(Printf.sprintf "%s <%s>" config.name config.email)
            ~who:config.name in
          match Ditz.Storage.save_issue config.issue_dir issue with
          | Ok () ->
            (match mode with
             | Json -> Fmt.pr "%s@." (Ditz.Types.simple_issue_json issue)
             | Quiet -> Fmt.pr "%s@." issue.id
             | Human -> Fmt.pr "Created issue %s@." issue.id);
            0
          | Error (`Msg e) ->
            Fmt.epr "Error: %s@." e; 1
  in
  Cmd.v info Term.(const run $ title_arg $ id_opt $ type_opt $ component_opt $ desc_opt $ desc_stdin_flag $ json_flag $ quiet_flag $ setup_log_term)

(* AGENTS.md lands at the working-tree root (where agents read it on arrival),
   not the cwd init happened to run from; falls back to cwd outside a repo. *)
let agents_md_path () =
  match Ditz.Git.find_git_root () with
  | Some root -> Filename.concat root "AGENTS.md"
  | None -> "AGENTS.md"

let onboard_cmd =
  let doc = "Write the ditz agent-onboarding block into AGENTS.md (re-runnable)" in
  let info = Cmd.info "onboard" ~doc in
  let run json quiet () =
    let mode = output_mode json quiet in
    let path = agents_md_path () in
    let outcome = Ditz.Onboarding.install ~within:(Ditz.Git.find_git_root ()) ~path in
    (* dest is the file actually touched (may be a symlink's resolved target). *)
    let ob, dest = match outcome with
      | Ditz.Onboarding.Wrote d -> "wrote", Some d
      | Skipped_present d -> "already-present", Some d
      | Refused_symlink -> "refused-symlink", None
      | Failed _ -> "failed", None
    in
    (match mode with
     | Json ->
       Fmt.pr {|{"path":"%s","onboarding":"%s"}@.|}
         (Ditz.Types.escape_json_string (Option.value dest ~default:path)) ob
     | Quiet -> (match dest with Some d -> Fmt.pr "%s@." d | None -> ())
     | Human ->
       (match outcome with
        | Wrote d -> Fmt.pr "Wrote ditz onboarding block to %s@." d
        | Skipped_present d -> Fmt.pr "%s already has the ditz onboarding block.@." d
        | Refused_symlink ->
          Fmt.epr "%s is a symlink; left it alone. Add the onboarding block to its target manually.@." path
        | Failed e -> Fmt.epr "Error: %s@." e));
    (match outcome with Failed _ -> 1 | _ -> 0)
  in
  Cmd.v info Term.(const run $ json_flag $ quiet_flag $ setup_log_term)

let init_cmd =
  let doc = "Initialize a new ditz project" in
  let info = Cmd.info "init" ~doc in
  let no_onboarding = Arg.(value & flag & info ["no-onboarding"] ~doc:"Don't write the ditz onboarding block into AGENTS.md") in
  let run no_onboarding json quiet () =
    let mode = output_mode json quiet in
    let name = Filename.basename (Sys.getcwd ()) in
    match Ditz.Storage.init_project ~name ~issue_dir:".ditz" with
    | Ok () ->
      (* Drop the agent-onboarding block into the repo-root AGENTS.md. Never
         fails init: a symlink (commonly -> a shared canonical file) or write
         error is reported, not fatal. (To (re)write it later, `ditz onboard`.) *)
      let onboarding =
        if no_onboarding then None
        else Some (Ditz.Onboarding.install ~within:(Ditz.Git.find_git_root ()) ~path:(agents_md_path ()))
      in
      (match mode with
       | Json ->
         let ob = match onboarding with
           | None -> "skipped"
           | Some (Ditz.Onboarding.Wrote _) -> "wrote"
           | Some (Skipped_present _) -> "already-present"
           | Some Refused_symlink -> "refused-symlink"
           | Some (Failed _) -> "failed"
         in
         Fmt.pr {|{"project":"%s","status":"initialized","onboarding":"%s"}@.|}
           (Ditz.Types.escape_json_string name) ob
       | Quiet -> Fmt.pr "%s@." name
       | Human ->
         Fmt.pr "Initialized ditz project '%s'@." name;
         (match onboarding with
          | None | Some (Skipped_present _) -> ()
          | Some (Wrote d) -> Fmt.pr "Wrote ditz onboarding block to %s@." d
          | Some Refused_symlink ->
            Fmt.epr "Note: AGENTS.md is a symlink; left it alone. Add the ditz \
                     onboarding block to its target manually if you want it.@."
          | Some (Failed e) -> Fmt.epr "Note: could not write AGENTS.md: %s@." e));
      0
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
  in
  Cmd.v info Term.(const run $ no_onboarding $ json_flag $ quiet_flag $ setup_log_term)

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
  let reason_opt = Arg.(value & opt (some string) None & info ["reason"] ~docv:"TEXT" ~doc:"Reason for closing (recorded on the close event)") in
  let run ids fixed wontfix reorg reason json quiet () =
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
            let issue = Ditz.Issue_ops.close_issue issue ~who:config.name ~disposition:disp ~comment:(Option.value reason ~default:"") in
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
  Cmd.v info Term.(const run $ ids_arg $ fixed_flag $ wontfix_flag $ reorg_flag $ reason_opt $ json_flag $ quiet_flag $ setup_log_term)

let reopen_cmd =
  let doc = "Reopen one or more closed issues" in
  let info = Cmd.info "reopen" ~doc in
  let ids_arg = Arg.(non_empty & pos_all string [] & info [] ~docv:"ID" ~doc:"Issue ID(s) (or prefix)") in
  let run ids json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let (reopened, errors) = List.fold_left (fun (ok, err) id ->
        match Ditz.Storage.find_issue_by_id config.issue_dir id with
        | Error (`Msg e) -> (ok, (id, e) :: err)
        | Ok issue ->
          match Ditz.Issue_ops.reopen_issue issue ~who:config.name with
          | Error (`Msg e) -> (ok, (id, e) :: err)
          | Ok issue ->
            match Ditz.Storage.save_issue config.issue_dir issue with
            | Ok () -> (issue :: ok, err)
            | Error (`Msg e) -> (ok, (id, e) :: err)
      ) ([], []) ids in
      let reopened = List.rev reopened in
      let errors = List.rev errors in
      (match mode with
       | Json ->
         let reopened_json = String.concat "," (List.map Ditz.Types.simple_issue_json reopened) in
         let errors_json = String.concat "," (List.map (fun (id, e) ->
           Printf.sprintf {|{"id":"%s","error":"%s"}|}
             (Ditz.Types.escape_json_string id)
             (Ditz.Types.escape_json_string e)
         ) errors) in
         Fmt.pr {|{"reopened":[%s],"errors":[%s]}@.|} reopened_json errors_json
       | Quiet ->
         List.iter (fun (i : Ditz.Types.issue) -> Fmt.pr "%s@." i.id) reopened
       | Human ->
         List.iter (fun (i : Ditz.Types.issue) -> Fmt.pr "Reopened issue %s@." i.id) reopened;
         List.iter (fun (id, e) -> Fmt.epr "Error reopening %s: %s@." id e) errors);
      if errors = [] then 0 else 1
  in
  Cmd.v info Term.(const run $ ids_arg $ json_flag $ quiet_flag $ setup_log_term)

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
      (* 7.4: order by graph leverage — how many open issues each transitively
         unblocks (descending) — then oldest-first, then id for stability.
         Score is computed once per ready issue (the comparator must not
         recompute the DFS). On a flat graph every score is 0 and this reduces
         to oldest-first (the documented blind spot for urgent-but-unblocking
         work). *)
      let score = Ditz.Graph.unblock_score all_issues in
      let scored = List.map (fun (i : Ditz.Types.issue) -> (i, score i.id)) ready_issues in
      let scored = List.sort (fun (a, sa) (b, sb) ->
        if sa <> sb then compare sb sa
        else
          let t = compare a.Ditz.Types.creation_time b.Ditz.Types.creation_time in
          if t <> 0 then t else compare a.Ditz.Types.id b.Ditz.Types.id
      ) scored in
      let ready_issues = List.map fst scored in
      (match mode with
       | Json ->
         Fmt.pr "%s@." (Ditz.Types.issues_to_json ready_issues)
       | Quiet ->
         List.iter (fun (i : Ditz.Types.issue) -> Fmt.pr "%s@." i.id) ready_issues
       | Human ->
         if scored = [] then
           Fmt.pr "No issues ready to work on.@."
         else begin
           Fmt.pr "Ready to work on (%d issues):@.@." (List.length scored);
           List.iter (fun ((issue : Ditz.Types.issue), s) ->
             let widget = Ditz.Types.status_widget issue.status in
             let unblocks = if s > 0 then Printf.sprintf " (unblocks %d)" s else "" in
             Fmt.pr "[%s] %s: %s%s@." widget issue.id issue.title unblocks
           ) scored
         end);
      0
  in
  Cmd.v info Term.(const run $ json_flag $ quiet_flag $ setup_log_term)

let comment_cmd =
  let doc = "Add a comment to an issue" in
  let info = Cmd.info "comment" ~doc in
  let id_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Issue ID (or prefix)") in
  let comment_arg = Arg.(value & pos 1 (some string) None & info [] ~docv:"COMMENT" ~doc:"Comment text (or use --stdin)") in
  let stdin_flag = Arg.(value & flag & info ["stdin"] ~doc:"Read comment from stdin") in
  let run id comment_text use_stdin json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let comment = match (comment_text, use_stdin) with
        | (Some c, false) -> c
        | (None, true) -> read_stdin ()
        | (Some _, true) ->
          Fmt.epr "Error: cannot use both comment argument and --stdin@."; ""
        | (None, false) ->
          Fmt.epr "Error: provide comment text or use --stdin@."; ""
      in
      if comment = "" then 1
      else
        match Ditz.Storage.find_issue_by_id config.issue_dir id with
        | Error (`Msg e) ->
          Fmt.epr "Error: %s@." e; 1
        | Ok issue ->
          let issue = Ditz.Issue_ops.add_comment issue ~who:config.name ~comment in
          match Ditz.Storage.save_issue config.issue_dir issue with
          | Ok () ->
            (match mode with
             | Json ->
               Fmt.pr {|{"id":"%s","commented":true}@.|} (Ditz.Types.escape_json_string issue.id)
             | Quiet -> Fmt.pr "%s@." issue.id
             | Human -> Fmt.pr "Added comment to %s@." issue.id);
            0
          | Error (`Msg e) ->
            Fmt.epr "Error: %s@." e; 1
  in
  Cmd.v info Term.(const run $ id_arg $ comment_arg $ stdin_flag $ json_flag $ quiet_flag $ setup_log_term)

(* Blocks command - add blocking relationship *)
let blocks_cmd =
  let doc = "Mark that an issue blocks another issue" in
  let info = Cmd.info "blocks" ~doc in
  let blocker_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"BLOCKER" ~doc:"Issue that blocks") in
  let blocked_arg = Arg.(required & pos 1 (some string) None & info [] ~docv:"BLOCKED" ~doc:"Issue that is blocked") in
  let run blocker_id blocked_id json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      (* Load the tracker once: both id lookups and the cycle check resolve
         against the same snapshot (was three loads). *)
      let all = Ditz.Storage.load_issues config.issue_dir in
      match Ditz.Storage.find_issue_by_id_in all blocker_id with
      | Error (`Msg e) ->
        Fmt.epr "Error finding blocker: %s@." e; 1
      | Ok blocker ->
        match Ditz.Storage.find_issue_by_id_in all blocked_id with
        | Error (`Msg e) ->
          Fmt.epr "Error finding blocked: %s@." e; 1
        | Ok blocked ->
          (* L1: refuse an edge that would close a dependency cycle. The
             traversal underlying ready-ordering is cycle-SAFE, but a cycle is
             still a nonsense state ("each waits on the other"), so we prevent
             it at the CLI rather than silently store it. (Hand-edit/sync can
             still introduce one; `deps --check` catches those.) *)
          if Ditz.Graph.blocks_would_cycle all
               ~blocker:blocker.id ~blocked:blocked.id then begin
            Fmt.epr "Error: %s blocks %s would create a dependency cycle (%s already \
                     blocks %s, directly or transitively). Run 'ditz deps --check'.@."
              blocker.id blocked.id blocked.id blocker.id;
            1
          end else
          (* Update both issues *)
          let blocker = Ditz.Issue_ops.add_blocks blocker ~blocked_id:blocked.id ~who:config.name in
          let blocked = Ditz.Issue_ops.add_blocked_by blocked ~blocker_id:blocker.id ~who:config.name in
          match Ditz.Storage.save_issue config.issue_dir blocker with
          | Error (`Msg e) ->
            Fmt.epr "Error saving blocker: %s@." e; 1
          | Ok () ->
            match Ditz.Storage.save_issue config.issue_dir blocked with
            | Error (`Msg e) ->
              Fmt.epr "Error saving blocked: %s@." e; 1
            | Ok () ->
              (match mode with
               | Json ->
                 Fmt.pr {|{"blocker":"%s","blocked":"%s"}@.|}
                   (Ditz.Types.escape_json_string blocker.id)
                   (Ditz.Types.escape_json_string blocked.id)
               | Quiet -> Fmt.pr "%s %s@." blocker.id blocked.id
               | Human -> Fmt.pr "%s now blocks %s@." blocker.id blocked.id);
              0
  in
  Cmd.v info Term.(const run $ blocker_arg $ blocked_arg $ json_flag $ quiet_flag $ setup_log_term)

(* L2: inspect/validate the dependency graph. The graph is already plain text
   in the files (grep/jq); deps renders and validates it over the same Graph
   traversal that powers ready-ordering — it is NOT stored state. The rendered
   tree is a pull command, deliberately kept out of `context`. *)
let deps_cmd =
  let doc = "Inspect and validate the dependency graph" in
  let info = Cmd.info "deps" ~doc in
  let id_arg = Arg.(value & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Show the blocks-subtree rooted at this issue") in
  let check_flag = Arg.(value & flag & info ["check"] ~doc:"Validate the whole graph (cycles, dangling refs, one-sided edges); nonzero exit on problems") in
  let dot_flag = Arg.(value & flag & info ["dot"] ~doc:"Emit the whole graph as Graphviz DOT") in
  let run id check dot json () =
    match Ditz.Storage.load_config () with
    | Error (`Msg e) -> Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let issues = Ditz.Storage.load_issues config.issue_dir in
      let title_of id =
        match List.find_opt (fun (i : Ditz.Types.issue) -> i.id = id) issues with
        | Some i -> i.title | None -> "(unknown)"
      in
      if dot then begin
        (* Whole-graph DOT: edges blocker -> blocked, from blocked_by. *)
        let esc s = Ditz.Types.escape_json_string s in
        Fmt.pr "digraph ditz {@.";
        List.iter (fun (i : Ditz.Types.issue) ->
          Fmt.pr "  \"%s\" [label=\"%s\"];@." (esc i.id) (esc i.title)) issues;
        List.iter (fun (i : Ditz.Types.issue) ->
          List.iter (fun a -> Fmt.pr "  \"%s\" -> \"%s\";@." (esc a) (esc i.id)) i.blocked_by)
          issues;
        Fmt.pr "}@.";
        0
      end
      else if check || id = None then begin
        let cycles = Ditz.Graph.find_cycles issues in
        let dangling = Ditz.Graph.dangling_refs issues in
        let one_sided = Ditz.Graph.one_sided_edges issues in
        let clean = cycles = [] && dangling = [] && one_sided = [] in
        if json then begin
          (* Each "cycle" is a strongly-connected component — a SET of mutually
             reachable ids, not an ordered path; the key name says so. *)
          let cyc_json = String.concat "," (List.map (fun c ->
            "[" ^ String.concat "," (List.map (fun x -> Printf.sprintf "\"%s\"" (Ditz.Types.escape_json_string x)) c) ^ "]") cycles) in
          let dang_json = String.concat "," (List.map (fun (i, m, rel) ->
            Printf.sprintf {|{"issue":"%s","missing":"%s","relation":"%s"}|}
              (Ditz.Types.escape_json_string i) (Ditz.Types.escape_json_string m) rel) dangling) in
          let os_json = String.concat "," (List.map (fun (a, b) ->
            Printf.sprintf {|{"blocker":"%s","blocked":"%s"}|}
              (Ditz.Types.escape_json_string a) (Ditz.Types.escape_json_string b)) one_sided) in
          Fmt.pr {|{"ok":%b,"cyclic_components":[%s],"dangling":[%s],"one_sided":[%s]}@.|}
            clean cyc_json dang_json os_json
        end else if clean then
          Fmt.pr "Dependency graph OK (%d issues, no cycles/dangling/one-sided edges).@."
            (List.length issues)
        else begin
          List.iter (fun c -> Fmt.pr "CYCLE (mutually blocking): %s@." (String.concat ", " c)) cycles;
          List.iter (fun (i, m, rel) -> Fmt.pr "DANGLING: %s %s %s (no such issue)@." i rel m) dangling;
          List.iter (fun (a, b) -> Fmt.pr "ONE-SIDED: %s blocks %s recorded on only one side@." a b) one_sided
        end;
        if clean then 0 else 1
      end
      else begin
        (* deps <id>: blocks-subtree (downstream) rooted at id *)
        let id = Option.get id in
        match Ditz.Storage.find_issue_by_id config.issue_dir id with
        | Error (`Msg e) -> Fmt.epr "Error: %s@." e; 1
        | Ok root ->
          if json then begin
            let lst l = "[" ^ String.concat "," (List.map (fun x -> Printf.sprintf "\"%s\"" (Ditz.Types.escape_json_string x)) l) ^ "]" in
            (* direct_blocks derived from the authoritative blocked_by adjacency
               (not the stored reciprocal blocks field), so all three views
               agree even on one-sided data. *)
            let direct_blocks =
              try Hashtbl.find (Ditz.Graph.blocks_adjacency issues) root.id
              with Not_found -> []
            in
            Fmt.pr {|{"id":"%s","blocks":%s,"blocked_by":%s,"transitively_blocks":%s}@.|}
              (Ditz.Types.escape_json_string root.id)
              (lst (List.sort compare direct_blocks)) (lst root.blocked_by)
              (lst (Ditz.Graph.transitively_blocks_list issues root.id))
          end else begin
            let adj = Ditz.Graph.blocks_adjacency issues in
            let rec walk depth path id =
              let indent = String.make (depth * 2) ' ' in
              if List.mem id path then Fmt.pr "%s%s (cycle)@." indent id
              else begin
                Fmt.pr "%s%s: %s@." indent id (title_of id);
                let succs = try Hashtbl.find adj id with Not_found -> [] in
                List.iter (walk (depth + 1) (id :: path)) (List.sort compare succs)
              end
            in
            walk 0 [] root.id
          end;
          0
      end
  in
  Cmd.v info Term.(const run $ id_arg $ check_flag $ dot_flag $ json_flag $ setup_log_term)

(* Unblocks command - remove blocking relationship *)
let unblocks_cmd =
  let doc = "Remove blocking relationship between issues" in
  let info = Cmd.info "unblocks" ~doc in
  let blocker_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"BLOCKER" ~doc:"Issue that was blocking") in
  let blocked_arg = Arg.(required & pos 1 (some string) None & info [] ~docv:"BLOCKED" ~doc:"Issue that was blocked") in
  let run blocker_id blocked_id json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      match Ditz.Storage.find_issue_by_id config.issue_dir blocker_id with
      | Error (`Msg e) ->
        Fmt.epr "Error finding blocker: %s@." e; 1
      | Ok blocker ->
        match Ditz.Storage.find_issue_by_id config.issue_dir blocked_id with
        | Error (`Msg e) ->
          Fmt.epr "Error finding blocked: %s@." e; 1
        | Ok blocked ->
          let blocker = Ditz.Issue_ops.remove_blocks blocker ~blocked_id:blocked.id ~who:config.name in
          let blocked = Ditz.Issue_ops.remove_blocked_by blocked ~blocker_id:blocker.id ~who:config.name in
          match Ditz.Storage.save_issue config.issue_dir blocker with
          | Error (`Msg e) ->
            Fmt.epr "Error saving blocker: %s@." e; 1
          | Ok () ->
            match Ditz.Storage.save_issue config.issue_dir blocked with
            | Error (`Msg e) ->
              Fmt.epr "Error saving blocked: %s@." e; 1
            | Ok () ->
              (match mode with
               | Json ->
                 Fmt.pr {|{"blocker":"%s","blocked":"%s","unblocked":true}@.|}
                   (Ditz.Types.escape_json_string blocker.id)
                   (Ditz.Types.escape_json_string blocked.id)
               | Quiet -> Fmt.pr "%s %s@." blocker.id blocked.id
               | Human -> Fmt.pr "%s no longer blocks %s@." blocker.id blocked.id);
              0
  in
  Cmd.v info Term.(const run $ blocker_arg $ blocked_arg $ json_flag $ quiet_flag $ setup_log_term)

(* Ref command - add file reference *)
let ref_cmd =
  let doc = "Add a file reference to an issue" in
  let info = Cmd.info "ref" ~doc in
  let id_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Issue ID") in
  let path_arg = Arg.(required & pos 1 (some string) None & info [] ~docv:"PATH" ~doc:"File path (optionally with :LINE)") in
  let note_opt = Arg.(value & opt (some string) None & info ["note"; "n"] ~docv:"NOTE" ~doc:"Note about this reference") in
  let run id path_spec note json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      (* Parse path:line format *)
      let (path, line) =
        match String.rindex_opt path_spec ':' with
        | None -> (path_spec, None)
        | Some i ->
          let after_colon = String.sub path_spec (i + 1) (String.length path_spec - i - 1) in
          match int_of_string_opt after_colon with
          | Some l -> (String.sub path_spec 0 i, Some l)
          | None -> (path_spec, None) (* Not a number, treat whole thing as path *)
      in
      match Ditz.Storage.find_issue_by_id config.issue_dir id with
      | Error (`Msg e) ->
        Fmt.epr "Error: %s@." e; 1
      | Ok issue ->
        let issue = Ditz.Issue_ops.add_file_ref issue ~path ~line ~note ~who:config.name in
        match Ditz.Storage.save_issue config.issue_dir issue with
        | Ok () ->
          let loc = match line with Some l -> Printf.sprintf "%s:%d" path l | None -> path in
          (match mode with
           | Json ->
             Fmt.pr {|{"id":"%s","ref":"%s"}@.|}
               (Ditz.Types.escape_json_string issue.id)
               (Ditz.Types.escape_json_string loc)
           | Quiet -> Fmt.pr "%s@." issue.id
           | Human -> Fmt.pr "Added reference %s to %s@." loc issue.id);
          0
        | Error (`Msg e) ->
          Fmt.epr "Error: %s@." e; 1
  in
  Cmd.v info Term.(const run $ id_arg $ path_arg $ note_opt $ json_flag $ quiet_flag $ setup_log_term)

(* Set command - update issue fields *)
let set_cmd =
  let doc = "Update issue fields" in
  let info = Cmd.info "set" ~doc in
  let id_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Issue ID") in
  let type_opt = Arg.(value & opt (some string) None & info ["type"; "t"] ~docv:"TYPE" ~doc:"Set issue type (bug, feature, task)") in
  let component_opt = Arg.(value & opt (some string) None & info ["component"; "c"] ~docv:"COMPONENT" ~doc:"Set component") in
  let title_opt = Arg.(value & opt (some string) None & info ["title"] ~docv:"TITLE" ~doc:"Set title") in
  let desc_opt = Arg.(value & opt (some string) None & info ["desc"; "d"] ~docv:"DESC" ~doc:"Set description") in
  let desc_stdin_flag = Arg.(value & flag & info ["desc-stdin"] ~doc:"Read description from stdin") in
  let status_opt = Arg.(value & opt (some string) None & info ["status"; "s"] ~docv:"STATUS" ~doc:"Set status (unstarted, in_progress, paused)") in
  let run id type_str component title desc desc_stdin status_str json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      match Ditz.Storage.find_issue_by_id config.issue_dir id with
      | Error (`Msg e) ->
        Fmt.epr "Error: %s@." e; 1
      | Ok issue ->
        (* Status first: it can fail (e.g. attempting to set Closed), and a
           failure should abort the whole set rather than partially apply. *)
        let status_result = match status_str with
          | None -> Ok issue
          | Some s ->
            match status_of_string s with
            | None -> Error (Printf.sprintf "unknown status '%s' (use unstarted, in_progress, paused)" s)
            | Some st ->
              (match Ditz.Issue_ops.set_status issue ~status:st ~who:config.name with
               | Ok i -> Ok i
               | Error (`Msg e) -> Error e)
        in
        match status_result with
        | Error e -> Fmt.epr "Error: %s@." e; 1
        | Ok issue ->
        (* Apply updates *)
        let issue = match type_str with
          | None -> issue
          | Some t ->
            match issue_type_of_string t with
            | None -> Fmt.epr "Warning: unknown type '%s'@." t; issue
            | Some typ -> Ditz.Issue_ops.set_type issue ~issue_type:typ ~who:config.name
        in
        let issue = match component with
          | None -> issue
          | Some c -> Ditz.Issue_ops.set_component issue ~component:c ~who:config.name
        in
        let issue = match title with
          | None -> issue
          | Some t -> Ditz.Issue_ops.set_title issue ~title:t ~who:config.name
        in
        let issue = match (desc, desc_stdin) with
          | (Some d, false) -> Ditz.Issue_ops.set_desc issue ~desc:d ~who:config.name
          | (None, true) -> Ditz.Issue_ops.set_desc issue ~desc:(read_stdin ()) ~who:config.name
          | (Some _, true) -> Fmt.epr "Warning: ignoring --desc-stdin since --desc provided@."; issue
          | (None, false) -> issue
        in
        match Ditz.Storage.save_issue config.issue_dir issue with
        | Ok () ->
          (match mode with
           | Json -> Fmt.pr "%s@." (Ditz.Types.simple_issue_json issue)
           | Quiet -> Fmt.pr "%s@." issue.id
           | Human -> Fmt.pr "Updated issue %s@." issue.id);
          0
        | Error (`Msg e) ->
          Fmt.epr "Error: %s@." e; 1
  in
  Cmd.v info Term.(const run $ id_arg $ type_opt $ component_opt $ title_opt $ desc_opt $ desc_stdin_flag $ status_opt $ json_flag $ quiet_flag $ setup_log_term)

(* Search command *)
let search_cmd =
  let doc = "Search issues by text" in
  let info = Cmd.info "search" ~doc in
  let query_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"QUERY" ~doc:"Search query") in
  let run query json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let all_issues = Ditz.Storage.load_issues config.issue_dir in
      let matches = List.filter (fun issue ->
        Ditz.Issue_ops.matches_search issue ~query
      ) all_issues in
      (match mode with
       | Json ->
         Fmt.pr "%s@." (Ditz.Types.issues_to_json matches)
       | Quiet ->
         List.iter (fun (i : Ditz.Types.issue) -> Fmt.pr "%s@." i.id) matches
       | Human ->
         if matches = [] then
           Fmt.pr "No issues match '%s'@." query
         else begin
           Fmt.pr "Found %d issue(s) matching '%s':@.@." (List.length matches) query;
           List.iter (fun (issue : Ditz.Types.issue) ->
             let widget = Ditz.Types.status_widget issue.status in
             Fmt.pr "[%s] %s: %s@." widget issue.id issue.title
           ) matches
         end);
      0
  in
  Cmd.v info Term.(const run $ query_arg $ json_flag $ quiet_flag $ setup_log_term)

(* Assign command - assign to release *)
let assign_cmd =
  let doc = "Assign issue to a release" in
  let info = Cmd.info "assign" ~doc in
  let id_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Issue ID") in
  let release_arg = Arg.(required & pos 1 (some string) None & info [] ~docv:"RELEASE" ~doc:"Release name") in
  let run id release json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      match Ditz.Storage.find_issue_by_id config.issue_dir id with
      | Error (`Msg e) ->
        Fmt.epr "Error: %s@." e; 1
      | Ok issue ->
        let issue = Ditz.Issue_ops.assign_release issue ~release ~who:config.name in
        match Ditz.Storage.save_issue config.issue_dir issue with
        | Ok () ->
          (match mode with
           | Json ->
             Fmt.pr {|{"id":"%s","release":"%s"}@.|}
               (Ditz.Types.escape_json_string issue.id)
               (Ditz.Types.escape_json_string release)
           | Quiet -> Fmt.pr "%s@." issue.id
           | Human -> Fmt.pr "Assigned %s to release %s@." issue.id release);
          0
        | Error (`Msg e) ->
          Fmt.epr "Error: %s@." e; 1
  in
  Cmd.v info Term.(const run $ id_arg $ release_arg $ json_flag $ quiet_flag $ setup_log_term)

(* Unassign command - remove from release *)
let unassign_cmd =
  let doc = "Remove issue from its release" in
  let info = Cmd.info "unassign" ~doc in
  let id_arg = Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc:"Issue ID") in
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
        let issue = Ditz.Issue_ops.unassign_release issue ~who:config.name in
        match Ditz.Storage.save_issue config.issue_dir issue with
        | Ok () ->
          (match mode with
           | Json ->
             Fmt.pr {|{"id":"%s","release":null}@.|} (Ditz.Types.escape_json_string issue.id)
           | Quiet -> Fmt.pr "%s@." issue.id
           | Human -> Fmt.pr "Unassigned %s from release@." issue.id);
          0
        | Error (`Msg e) ->
          Fmt.epr "Error: %s@." e; 1
  in
  Cmd.v info Term.(const run $ id_arg $ json_flag $ quiet_flag $ setup_log_term)

(* Status command - project overview *)
let status_cmd =
  let doc = "Show project status overview" in
  let info = Cmd.info "status" ~doc in
  let run json quiet () =
    let mode = output_mode json quiet in
    match Ditz.Storage.load_config () with
    | Error (`Msg e) ->
      Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      let issues = Ditz.Storage.load_issues config.issue_dir in
      (* Count by status *)
      let count_status st = List.length (List.filter (fun (i : Ditz.Types.issue) -> i.status = st) issues) in
      let unstarted = count_status Ditz.Types.Unstarted in
      let in_progress = count_status Ditz.Types.In_progress in
      let paused = count_status Ditz.Types.Paused in
      let closed = count_status Ditz.Types.Closed in
      (* Count by type (open only) *)
      let open_issues = List.filter (fun (i : Ditz.Types.issue) -> i.status <> Ditz.Types.Closed) issues in
      let count_type t = List.length (List.filter (fun (i : Ditz.Types.issue) -> i.issue_type = t) open_issues) in
      let bugs = count_type Ditz.Types.Bugfix in
      let features = count_type Ditz.Types.Feature in
      let tasks = count_type Ditz.Types.Task in
      (match mode with
       | Json ->
         Fmt.pr {|{"total":%d,"open":%d,"unstarted":%d,"in_progress":%d,"paused":%d,"closed":%d,"bugs":%d,"features":%d,"tasks":%d}@.|}
           (List.length issues) (List.length open_issues) unstarted in_progress paused closed bugs features tasks
       | Quiet ->
         Fmt.pr "%d %d %d %d %d@." (List.length open_issues) unstarted in_progress paused closed
       | Human ->
         Fmt.pr "Project Status@.@.";
         Fmt.pr "Total issues: %d@." (List.length issues);
         Fmt.pr "Open: %d (unstarted: %d, in progress: %d, paused: %d)@."
           (List.length open_issues) unstarted in_progress paused;
         Fmt.pr "Closed: %d@.@." closed;
         Fmt.pr "Open by type:@.";
         Fmt.pr "  Bugs: %d@." bugs;
         Fmt.pr "  Features: %d@." features;
         Fmt.pr "  Tasks: %d@." tasks);
      0
  in
  Cmd.v info Term.(const run $ json_flag $ quiet_flag $ setup_log_term)

let sync_cmd =
  let doc = "Sync ditz-metadata with remote (fetch, merge, push)" in
  let info = Cmd.info "sync" ~doc in
  let pull_only = Arg.(value & flag & info ["pull-only"] ~doc:"Only fetch and merge, don't push") in
  let push_only = Arg.(value & flag & info ["push-only"] ~doc:"Only push, don't fetch or merge") in
  let run pull_only push_only () =
    if not (Ditz.Git.is_git_repo ()) then begin
      Fmt.epr "Error: not in a git repository@."; 1
    end else if not (Ditz.Git.ditz_metadata_exists ()) then begin
      Fmt.epr "Error: ditz-metadata branch does not exist. Run 'ditz init' first.@."; 1
    end else begin
      match (pull_only, push_only) with
      | (true, true) ->
        Fmt.epr "Error: specify at most one of --pull-only, --push-only@."; 1
      | (true, false) ->
        (* Pull only: fetch and merge *)
        (match Ditz.Git.fetch () with
         | Error (`Msg e) -> Fmt.epr "Error fetching: %s@." e; 1
         | Ok () ->
           match Ditz.Git.merge () with
           | Error (`Msg e) -> Fmt.epr "Error merging: %s@." e; 1
           | Ok () -> Fmt.pr "Synced (pull only)@."; 0)
      | (false, true) ->
        (* Push only *)
        (match Ditz.Git.push () with
         | Error (`Msg e) -> Fmt.epr "Error pushing: %s@." e; 1
         | Ok () -> Fmt.pr "Pushed ditz-metadata@."; 0)
      | (false, false) ->
        (* Full sync *)
        (match Ditz.Git.sync () with
         | Error (`Msg e) -> Fmt.epr "Error: %s@." e; 1
         | Ok () -> Fmt.pr "Synced ditz-metadata@."; 0)
    end
  in
  Cmd.v info Term.(const run $ pull_only $ push_only $ setup_log_term)

let import_cmd =
  let doc = "Import issues from a beads `bd export` JSONL file" in
  let man =
    [ `S Manpage.s_description;
      `P "Imports issues from a beads `bd export` JSONL file. The import is \
          idempotent: an issue whose id is already present is left untouched.";
      `P "Ids beads allows but ditz does not (e.g. dotted child ids such as \
          $(b,goals-53u.1)) are renamed, not dropped, and every edge endpoint \
          is rewritten to match. The original id is recorded in the issue's \
          provenance. A beads $(b,parent-child) dependency becomes a blocking \
          edge from child to parent, since an epic is not done until its \
          children are. $(b,acceptance_criteria) is folded into the issue \
          description.";
      `P "An import is incremental: ids and edge endpoints are resolved \
          against the issues already in the tracker, not just the file. A \
          rename that would land on an id an unrelated issue already holds is \
          refused rather than silently merged into it; re-importing the same \
          issue is still an idempotent skip, proven by its beads_id \
          provenance. An edge whose far side is an issue already present has \
          that side completed, so no relationship is left recorded on one \
          side only.";
      `P "Exit status is 0 only when every issue imported without data loss. \
          Anything dropped — an unparseable line, a field present with the \
          wrong type, a colliding id, an issue ditz cannot store, a dependency \
          edge to an id that will not exist — is reported as a warning and \
          exits non-zero. Lossless outcomes are notices and do not affect the \
          exit status: a rename, a completed far side, and any beads value \
          ditz has no field for but keeps in provenance (priority, labels, \
          unrecognized types and statuses)." ]
  in
  let info = Cmd.info "import" ~doc ~man in
  let file_arg = Arg.(value & pos 0 (some string) None & info [] ~docv:"FILE" ~doc:"JSONL file ('-' or omitted = stdin)") in
  let format_opt = Arg.(value & opt string "beads" & info ["format"] ~docv:"FMT" ~doc:"Source format (only 'beads' supported)") in
  let run file format json quiet () =
    let mode = output_mode json quiet in
    if format <> "beads" then begin
      Fmt.epr "Error: unknown import format '%s' (only 'beads' is supported)@." format; 1
    end else
    match Ditz.Storage.load_config () with
    | Error (`Msg e) -> Fmt.epr "Error: %s@." e; 1
    | Ok config ->
      (* Read JSONL from the file or stdin. *)
      let text =
        match file with
        | None | Some "-" -> read_stdin ()
        | Some path ->
          (try Ditz.Fs_util.read_file path
           with Sys_error e -> Fmt.epr "Error reading %s: %s@." path e; exit 1)
      in
      let beads, parse_warns = Ditz.Import_beads.parse_jsonl text in
      let valid id = Result.is_ok (Ditz.Storage.validate_id id) in
      (* An import is incremental, not a fresh world: the tracker already holds
         issues, and both id collisions and edge endpoints have to be judged
         against them. Load once. *)
      let existing = Ditz.Storage.load_issues config.issue_dir in
      let existing_ids = Hashtbl.create (List.length existing) in
      List.iter (fun (i : Ditz.Types.issue) -> Hashtbl.replace existing_ids i.id i) existing;
      (* Issues whose file is there but unreadable. load_issues drops them with
         a log warning, so without this they look absent -- and the create path
         would overwrite data it could not even read. *)
      let unreadable = Hashtbl.create 4 in
      List.iter
        (fun id -> Hashtbl.replace unreadable id ())
        (Ditz.Storage.unreadable_ids config.issue_dir);
      (* Does the issue already stored under [id] descend from beads issue
         [beads_id]? Re-importing the same renamed issue must stay the benign
         idempotent skip; only an UNRELATED occupant is a collision. Identity is
         proven by the beads_id= provenance the first import wrote. *)
      let is_same_beads_issue id beads_id =
        match Hashtbl.find_opt existing_ids id with
        | None -> false
        | Some (i : Ditz.Types.issue) ->
          Ditz.Import_beads.issue_has_beads_id i beads_id
      in
      (* Rename ids ditz can't store (beads' dotted child ids) rather than
         dropping the issue, rewriting every edge endpoint to match. Runs BEFORE
         dedup and reciprocal reconstruction so no stale id survives in a
         reverse edge. A rename onto an id an unrelated issue already holds is
         refused rather than silently merged. *)
      let beads, rename_notices, rename_warns =
        Ditz.Import_beads.sanitize_ids
          ~taken:(fun ~orig ~renamed ->
            Hashtbl.mem existing_ids renamed && not (is_same_beads_issue renamed orig))
          (* Resolve an endpoint that names no record in this file. An id the
             tracker already holds resolves to itself. A beads id needing a
             rename resolves ONLY to an issue that proves it descends from that
             beads id; otherwise the sanitized form could name an unrelated
             issue that merely happens to occupy it, and the edge would attach
             to the wrong thing. Unresolved ids fall through to the existence
             check, which drops and warns. *)
          ~resolve_external:(fun id ->
            if Hashtbl.mem existing_ids id then Some id
            else
              let s = Ditz.Import_beads.sanitize_id id in
              if s <> id && Hashtbl.mem existing_ids s && is_same_beads_issue s id then Some s
              else None)
          beads
      in
      (* Drop in-file duplicate ids (keep first). *)
      let beads, dup_warns = Ditz.Import_beads.dedup beads in
      (* Anything still unstorable after renaming (an empty id) is dropped, and
         that must happen BEFORE reciprocal reconstruction — otherwise a skipped
         issue would still leak its id into a valid issue's `blocks` via the
         reverse edge (save_issue only validates an issue's own id, not its
         relation ids). [council convergence] *)
      let beads, id_warns =
        let ok, bad = List.partition (fun (b : Ditz.Import_beads.bead) -> valid b.id) beads in
        (ok, List.map (fun (b : Ditz.Import_beads.bead) -> Printf.sprintf "skipped invalid issue id '%s'" b.id) bad)
      in
      (* An edge may only survive if its endpoint will exist afterwards: a
         record in this import, or an issue the tracker already holds. Keeping a
         dangling edge would leave `ditz deps --check` rejecting the graph. *)
      let importing = Hashtbl.create (List.length beads) in
      List.iter (fun (b : Ditz.Import_beads.bead) -> Hashtbl.replace importing b.id ()) beads;
      let known id = Hashtbl.mem importing id || Hashtbl.mem existing_ids id in
      let beads, edge_warns = Ditz.Import_beads.sanitize_edges ~known beads in
      let reciprocal = Ditz.Import_beads.reciprocal_blocks beads in
      let children = Ditz.Import_beads.children_by_parent beads in
      let reporter_fallback = Printf.sprintf "%s <%s>" config.name config.email in
      let warnings = ref (parse_warns @ rename_warns @ dup_warns @ id_warns @ edge_warns) in
      let notices = ref rename_notices in
      let created = ref [] and skipped = ref [] in
      (* Reciprocal edges landing on issues we are NOT creating (already
         present, or never in this file). Recorded here and written afterwards,
         because leaving one side unwritten is exactly the ONE-SIDED state
         `deps --check` rejects. *)
      let patch_existing : (string, string list * string list) Hashtbl.t = Hashtbl.create 8 in
      let note_existing_edge ~on ~blocks ~blocked_by =
        (* existing_ids was loaded before any write, so anything in it is
           pre-existing and the create loop will skip it -- whether or not this
           file also mentions it. Its far side is therefore ours to complete. *)
        if Hashtbl.mem existing_ids on then begin
          let b0, bb0 = Option.value (Hashtbl.find_opt patch_existing on) ~default:([], []) in
          Hashtbl.replace patch_existing on (blocks @ b0, blocked_by @ bb0)
        end
      in
      List.iter
        (fun (b : Ditz.Import_beads.bead) ->
          match Ditz.Storage.find_issue_by_exact_id config.issue_dir b.id with
          | Ok _ ->
            (* Idempotent: an existing issue keeps its fields. Its edges still
               have to be completed, or the sides disagree. *)
            skipped := b.id :: !skipped
          | Error _ when Hashtbl.mem unreadable b.id ->
            (* Absent and unreadable are different answers. Creating over the
               second destroys an issue we never managed to read. *)
            warnings :=
              Printf.sprintf
                "%s: an issue file for this id exists but could not be read; refusing to overwrite it"
                b.id
              :: !warnings
          | Error _ ->
            let blocks = Option.value (Hashtbl.find_opt reciprocal b.id) ~default:[] in
            let blocked_by_extra = Option.value (Hashtbl.find_opt children b.id) ~default:[] in
            let issue = Ditz.Import_beads.to_issue ~reporter_fallback ~blocks ~blocked_by_extra b in
            (match Ditz.Storage.save_issue ~commit_msg:(Printf.sprintf "ditz: import %s from beads" b.id)
                     config.issue_dir issue with
             | Ok () ->
               created := b.id :: !created;
               (* Queued only now that the issue is actually on disk. Queuing
                  before the save meant a failed save still pointed existing
                  issues at an id that was never written -- manufacturing the
                  dangling edge this whole change exists to prevent. *)
               List.iter (fun t -> note_existing_edge ~on:t ~blocks:[] ~blocked_by:[ issue.id ]) issue.blocks;
               List.iter (fun t -> note_existing_edge ~on:t ~blocks:[ issue.id ] ~blocked_by:[]) issue.blocked_by
             | Error (`Msg e) -> warnings := Printf.sprintf "failed to save %s: %s" b.id e :: !warnings))
        beads;
      (* Complete the far side of every edge that points at a pre-existing
         issue. Additive only -- no field of theirs is touched -- so it is a
         notice, not loss. *)
      Hashtbl.iter
        (fun id (add_blocks, add_blocked_by) ->
          match Hashtbl.find_opt existing_ids id with
          | None -> ()
          | Some (i : Ditz.Types.issue) ->
            let merged_blocks = Ditz.Import_beads.dedup_strings (i.blocks @ add_blocks) in
            let merged_blocked_by = Ditz.Import_beads.dedup_strings (i.blocked_by @ add_blocked_by) in
            if merged_blocks <> i.blocks || merged_blocked_by <> i.blocked_by then begin
              let updated = { i with blocks = merged_blocks; blocked_by = merged_blocked_by } in
              match
                Ditz.Storage.save_issue
                  ~commit_msg:(Printf.sprintf "ditz: complete edges on %s from beads import" id)
                  config.issue_dir updated
              with
              | Ok () ->
                notices :=
                  Printf.sprintf "completed the other side of an edge on existing issue '%s'" id
                  :: !notices
              | Error (`Msg e) ->
                warnings := Printf.sprintf "failed to complete edges on %s: %s" id e :: !warnings
            end)
        patch_existing;
      let notices = List.rev !notices in
      let created = List.rev !created and skipped = List.rev !skipped in
      let warnings = List.rev !warnings in
      (match mode with
       | Json ->
         let lst l = "[" ^ String.concat "," (List.map (fun s -> Printf.sprintf "\"%s\"" (Ditz.Types.escape_json_string s)) l) ^ "]" in
         Fmt.pr {|{"created":%s,"skipped":%s,"warnings":%s,"notices":%s}@.|}
           (lst created) (lst skipped) (lst warnings) (lst notices)
       | Quiet -> List.iter (fun id -> Fmt.pr "%s@." id) created
       | Human ->
         List.iter (fun n -> Fmt.epr "note: %s@." n) notices;
         List.iter (fun w -> Fmt.epr "warning: %s@." w) warnings;
         Fmt.pr "Imported %d issue(s) from beads; %d already present (skipped).@."
           (List.length created) (List.length skipped);
         if warnings <> [] then
           Fmt.epr "Import INCOMPLETE: %d problem(s) above lost data; exiting non-zero.@."
             (List.length warnings));
      (* Exit status is the only signal a script reliably reads, so anything
         that lost data fails the command. Renames are lossless and stay
         notices, and an already-present issue is idempotent re-import, not a
         problem — neither affects the status. *)
      if warnings = [] then 0 else 1
  in
  Cmd.v info Term.(const run $ file_arg $ format_opt $ json_flag $ quiet_flag $ setup_log_term)

let main_cmd =
  let doc = "Distributed issue tracker" in
  let info = Cmd.info "ditz" ~version:"0.1.0-ocaml" ~doc in
  Cmd.group info [
    list_cmd;
    add_cmd;
    init_cmd;
    onboard_cmd;
    show_cmd;
    close_cmd;
    reopen_cmd;
    start_cmd;
    stop_cmd;
    drop_cmd;
    context_cmd;
    ready_cmd;
    comment_cmd;
    blocks_cmd;
    unblocks_cmd;
    deps_cmd;
    ref_cmd;
    set_cmd;
    search_cmd;
    assign_cmd;
    unassign_cmd;
    status_cmd;
    sync_cmd;
    import_cmd;
  ]

let () = exit (Cmd.eval' main_cmd)
