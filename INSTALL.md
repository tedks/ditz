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
- **homes-imac** (macOS): the flake targets darwin (`x86_64-darwin` /
  `aarch64-darwin`) via `flake-utils.eachDefaultSystem`, so the same
  `nix profile install` command *should* work. This has NOT been verified from
  the Linux build host. Before relying on it, confirm the build resolves on the
  iMac:
  ```
  nix build github:tedks/ditz#ditz && ./result/bin/ditz --version
  ```
  If opam-nix fails to resolve a dependency on darwin, file an issue — that is a
  flake fix, not an install-procedure problem.

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
