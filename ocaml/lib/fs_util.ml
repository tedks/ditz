(** Shared file I/O primitives with the safety properties the trackers need:
    reads that never leak a channel, writes that are atomic and do not follow
    symlinks at the destination. Used by both the filesystem and git backends. *)

(** Read a whole file. The channel is closed even if reading raises. *)
let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

(** Write [content] to [path] atomically: write a fresh temp file in the same
    directory, then rename over the destination. Readers never observe a
    partial file (crash mid-write leaves only a temp file), and because the
    temp file is created fresh and rename replaces the destination inode, a
    symlink planted at [path] is replaced rather than followed.

    Deliberate tradeoffs: files land with open_temp_file's 0600 mode (the
    git history, not the worktree file, is the source of truth, and git
    re-checkouts normalize modes); no fsync before rename (power-loss
    durability is delegated to the git object store — the guarantee here is
    against torn writes from process death); symlinks in PARENT directories
    are followed — the defense is scoped to the destination entry itself. *)
let write_file_atomic ~path ~content =
  let dir = Filename.dirname path in
  let base = Filename.basename path in
  match Filename.open_temp_file ~temp_dir:dir (base ^ ".tmp-") "" with
  | exception Sys_error e ->
    Error (`Msg (Printf.sprintf "Failed to create temp file for %s: %s" path e))
  | temp_path, oc ->
    (try
       output_string oc content;
       close_out oc;
       Unix.rename temp_path path;
       Ok ()
     with exn ->
       close_out_noerr oc;
       (try Sys.remove temp_path with _ -> ());
       Error (`Msg (Printf.sprintf "Failed to write %s: %s" path (Printexc.to_string exn))))
