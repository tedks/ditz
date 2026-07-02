# Installing ditz

ditz is distributed as a Nix flake. Every machine builds (or substitutes) the
binary for its own system, so there is no cross-CPU compatibility concern across
a heterogeneous fleet — no prebuilt-binary portability traps.

> Legacy note: the old `INSTALL` file (no `.md`) documents the original Ruby
> ditz via RubyGems. This file is for the OCaml rewrite.

## Prerequisites

- **Nix** with flakes enabled. If `nix flake --help` errors, enable flakes once:
  ```
  mkdir -p ~/.config/nix
  echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
  ```

## Install (canonical)

Install `ditz` into your user profile from GitHub:

```
nix profile install github:tedks/ditz#ditz
```

> Recent Nix renamed `install` to `add` and prints
> `warning: 'install' is a deprecated alias for 'add'`. The command still works;
> use `nix profile add github:tedks/ditz#ditz` instead on Nix that has `add`
> (older Nix only has `install`). `install` is the widest-compatibility form.

`ditz` is now on your `PATH`. Verify:

```
ditz --version      # -> 0.1.0-ocaml
ditz --help
```

The first build compiles the OCaml toolchain via opam-nix (~10–15 min, cold). It
is cached afterward, and the `/nix/store` cache is shared across builds on the
same machine.

## Try without installing

Run it ephemerally — nothing is added to your profile:

```
nix run github:tedks/ditz -- list
nix run github:tedks/ditz -- --help
```

## Upgrading

```
nix profile upgrade ditz        # or: nix profile upgrade '.*'
```

This re-fetches the flake's default branch (master) and rebuilds if it changed.

## Pinning (reproducible across the fleet)

`nix profile install github:tedks/ditz#ditz` tracks master. To pin every machine
to the same revision, install from a specific commit:

```
nix profile install github:tedks/ditz/<commit-sha>#ditz
```

For a dotfiles-managed setup, record the chosen `<commit-sha>` there and install
from it, so all machines converge on one reviewed revision rather than whatever
master happens to be.

## Per-machine notes (tedks fleet)

- **drynwyn / splinter0 / tower0 / framework0** (Linux x86_64): the canonical
  install works as-is. Because each host builds for its own system, the
  Xeon/`target-cpu=native` portability issues that bite prebuilt binaries do not
  apply here — there is no prebuilt binary being copied between hosts.
- **macOS: requires macOS 14 (Sonoma) or newer.** The flake targets darwin
  (`x86_64-darwin` / `aarch64-darwin`), so `nix profile install
  github:tedks/ditz#ditz` works on a current macOS. On older macOS it does not,
  for two independent reasons found by testing on homes-imac (macOS 12.7.2,
  2026-06):
  - Current **Nix** (2.34.x) won't run on macOS < 14 — `libnixexpr` imports a
    `std::pmr` symbol Apple's libc++ only exports on macOS 14+ (`dyld: Symbol
    not found` → abort). (Pinning an older Nix, ≤ 2.29.x, gets Nix running on
    macOS 12, but see the next point.)
  - Current **nixpkgs** darwin packages won't run on macOS < 13 — e.g.
    `coreutils` (in every build sandbox) needs `mkfifoat`, a libSystem symbol
    added in macOS 13. So even with an older Nix, the ditz build fails at
    `unpackPhase`.

  Net: macOS 12 (Monterey) is unsupported; upgrade to macOS 14+ and the
  canonical install works. This is an OS-age/nixpkgs limitation, not a ditz or
  flake bug — there is no ditz-side fix.

## Fallback: build from a dev shell (no profile install)

On a machine where you already use the dev shell, you can build and copy the
binary yourself:

```
git clone https://github.com/tedks/ditz && cd ditz
nix develop --command bash -c 'cd ocaml && dune build'
# the binary is at ocaml/_build/default/bin/main.exe (installed name: ditz)
cp ocaml/_build/default/bin/main.exe ~/.local/bin/ditz
```

## Uninstall

```
nix profile remove ditz
```

## After installing

ditz onboards agents into a repo on `ditz init` (writes an onboarding block to
`AGENTS.md`; see `FORMAT.md` for the issue format and git model). To start using
it in a project:

```
cd your-project
ditz init        # creates the ditz-metadata branch + AGENTS.md onboarding
ditz add "First issue" -t task
ditz ready
```
