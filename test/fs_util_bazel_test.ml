let expect condition message = if not condition then failwith message

let expect_ok = function
  | Ok () -> ()
  | Error (`Msg message) -> failwith message

let () =
  let parent = match Sys.getenv_opt "TEST_TMPDIR" with
    | Some path -> path
    | None -> Filename.get_temp_dir_name () in
  let dir = Filename.temp_file ~temp_dir:parent "ditz_fs_util_bazel_" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o700;
  let path = Filename.concat dir "issue.yaml" in
  let victim = Filename.concat dir "victim.txt" in
  let link = Filename.concat dir "link.yaml" in
  Fun.protect
    ~finally:(fun () ->
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [path; victim; link];
      Unix.rmdir dir)
    (fun () ->
      expect_ok (Fs_util.write_file_atomic ~path ~content:"first\n");
      expect (Fs_util.read_file path = "first\n") "write/read round trip";
      expect_ok (Fs_util.write_file_atomic ~path ~content:"second\n");
      expect (Fs_util.read_file path = "second\n") "atomic overwrite";
      expect (Array.to_list (Sys.readdir dir) = ["issue.yaml"])
        "temporary file remained after successful write";
      expect_ok (Fs_util.write_file_atomic ~path:victim ~content:"safe\n");
      Unix.symlink victim link;
      expect_ok (Fs_util.write_file_atomic ~path:link ~content:"new\n");
      expect (Fs_util.read_file victim = "safe\n")
        "destination symlink followed into victim";
      expect (Fs_util.read_file link = "new\n")
        "destination symlink was not replaced";
      expect ((Unix.lstat link).Unix.st_kind = Unix.S_REG)
        "replacement is not a regular file";
      (match Fs_util.entry_exists path with
       | Ok true -> ()
       | _ -> failwith "existing path not found");
      (match Fs_util.entry_exists (Filename.concat dir "missing") with
       | Ok false -> ()
       | _ -> failwith "missing path reported present");
      (match Fs_util.write_file_atomic
               ~path:(Filename.concat dir "missing/issue.yaml") ~content:"x" with
       | Error (`Msg _) -> ()
       | Ok () -> failwith "missing parent accepted"))
