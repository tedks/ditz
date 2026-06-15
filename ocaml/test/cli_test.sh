#!/usr/bin/env bash
# CLI-eval smoke test: drives the built binary so cmdliner term construction,
# flag wiring, and exit codes are exercised under `dune runtest`. The pure
# library tests do NOT call Cmd.eval, so a duplicate-flag/arity regression
# (e.g. the -q vs log-verbosity collision) or an idempotency regression would
# otherwise reach CI green. $1 is the ditz binary.
set -u
# dune passes the binary as a path relative to the test run dir; resolve to
# absolute before we cd into the temp workdir.
BIN="$(realpath "$1")"
fail=0
check() { # check <desc> <expected-exit> <actual-exit>
  if [ "$2" != "$3" ]; then echo "FAIL: $1 (expected exit $2, got $3)"; fail=1
  else echo "ok: $1"; fi
}
contains() { # contains <desc> <needle> <haystack>
  case "$3" in *"$2"*) echo "ok: $1";; *) echo "FAIL: $1 (missing '$2' in: $3)"; fail=1;; esac
}

work="$(mktemp -d)"
export HOME="$work" DITZ_USER="CLI Test" DITZ_EMAIL="cli@test.local"
cd "$work"

# Every subcommand must at least construct its term (--help) without crashing.
# This is what would have caught the -q/log-verbosity duplicate-flag crash.
for sub in list add init show close reopen start stop drop context ready \
           comment blocks unblocks deps ref set search assign unassign status sync; do
  out="$("$BIN" "$sub" --help 2>&1)"; rc=$?
  check "$sub --help constructs" 0 "$rc"
done

"$BIN" init >/dev/null 2>&1

# 7.3 one-shot creation
id="$("$BIN" add "Login fails" -t bugfix -c auth --desc "repro steps" --ids-only)"; rc=$?
check "add one-shot --ids-only" 0 "$rc"
contains "add set type" '"type":"bugfix"' "$("$BIN" show "$id" --json)"
contains "add set component" '"component":"auth"' "$("$BIN" show "$id" --json)"

out="$("$BIN" add "Bad" -t epic 2>&1)"; check "add bad --type rejected" 1 "$?"
contains "add bad --type names valid" "bugfix, feature, task" "$out"
n="$("$BIN" list --ids-only | wc -l | tr -d ' ')"
contains "bad --type created nothing" "1" "$n"

# idempotent --id: returns existing unchanged, even with a bad creation flag
"$BIN" add "First" --id idem1 -t feature --ids-only >/dev/null
again="$("$BIN" add "Second" --id idem1 -t notatype --ids-only)"; rc=$?
check "idempotent re-add w/ bad type still succeeds" 0 "$rc"
contains "idempotent returns same id" "idem1" "$again"
contains "idempotent left type unchanged" '"type":"feature"' "$("$BIN" show idem1 --json)"

# 7.2 status as data
"$BIN" close "$id" --wontfix --reason "superseded" >/dev/null 2>&1
contains "close --reason on log event" "superseded" "$("$BIN" show "$id")"
out="$("$BIN" start "$id" 2>&1)"; check "start on closed errors" 1 "$?"
contains "start-on-closed names remedy" "reopen it first" "$out"
"$BIN" reopen "$id" >/dev/null 2>&1; check "reopen closed" 0 "$?"
out="$("$BIN" reopen "$id" 2>&1)"; check "reopen non-closed errors" 1 "$?"
"$BIN" set "$id" --status in_progress --ids-only >/dev/null 2>&1; check "set --status open" 0 "$?"
out="$("$BIN" set "$id" --status closed 2>&1)"; check "set --status closed refused" 1 "$?"
contains "set-closed names remedy" "use 'close" "$out"
out="$("$BIN" set "$id" --status bogus 2>&1)"; check "set --status bogus rejected" 1 "$?"

# --json stays clean (no hint leakage): ready --json parses as a JSON array
"$BIN" close "$id" --fixed >/dev/null 2>&1
rj="$("$BIN" ready --json 2>/dev/null)"
case "$rj" in \[*\]) echo "ok: ready --json is a clean array";; *) echo "FAIL: ready --json not clean: $rj"; fail=1;; esac

# Step 3: deps command + L1 cycle prevention
"$BIN" add "dep a" --id da --ids-only >/dev/null
"$BIN" add "dep b" --id db --ids-only >/dev/null
"$BIN" add "dep c" --id dc --ids-only >/dev/null
"$BIN" blocks da db >/dev/null 2>&1; "$BIN" blocks db dc >/dev/null 2>&1   # da->db->dc
out="$("$BIN" blocks dc da 2>&1)"; check "L1 refuses cycle-closing edge" 1 "$?"
contains "cycle refusal explains" "cycle" "$out"
out="$("$BIN" blocks da da 2>&1)"; check "L1 refuses self-block" 1 "$?"
contains "deps subtree shows chain" "dc" "$("$BIN" deps da)"
"$BIN" deps --check >/dev/null 2>&1; check "deps --check clean exits 0" 0 "$?"
contains "deps --json has transitively_blocks" "transitively_blocks" "$("$BIN" deps da --json)"
contains "deps --dot emits digraph" "digraph ditz" "$("$BIN" deps --dot)"

# deps --check DETECTS a hand-edited bad graph (dangling ref) and exits nonzero.
# Cycles can't be made via the CLI (L1), so write a bad issue file directly.
cat > .ditz/issue-bad1.yaml <<'YAML'
id: bad1
title: Bad
desc: ""
type: task
component: default
release:
reporter: S <s@e.co>
status: unstarted
disposition:
creation_time: 2026-06-15T00:00:00Z
references: []
log_events: []
blocked_by:
- nonexistent-id
YAML
out="$("$BIN" deps --check 2>&1)"; check "deps --check flags bad graph" 1 "$?"
contains "deps --check reports dangling" "DANGLING" "$out"
contains "deps --check --json not ok" '"ok":false' "$("$BIN" deps --check --json)"

if [ "$fail" = 0 ]; then echo "All CLI smoke tests passed"; else echo "CLI smoke tests FAILED"; fi
exit "$fail"
