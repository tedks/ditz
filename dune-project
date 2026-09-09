(lang dune 3.0)
(name ditz)
(generate_opam_files true)

(package
 (name ditz)
 (synopsis "Distributed issue tracker")
 (description "A simple, light-weight distributed issue tracker designed to work with git")
 (authors "Edward Smith")
 (maintainers "Edward Smith")
 (license "GPL-3.0-or-later")
 (source (github tedks/ditz))
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.0))
  cmdliner
  yaml
  ppx_deriving
  ppx_deriving_yaml
  digestif
  fmt
  logs
  ptime))
