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
# init writes the onboarding block into AGENTS.md (clobber-safe)
contains "init writes AGENTS.md onboarding" "ditz ready" "$(cat AGENTS.md 2>/dev/null)"
# `ditz onboard` is re-runnable and idempotent (AGENTS.md already has the block)
contains "onboard idempotent" "already-present" "$("$BIN" onboard --json 2>&1)"

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

# A real cycle can't be made via the CLI (L1), so write a reciprocal pair
# directly. This covers the CYCLE branch, the ASCII-tree cycle marking, and
# tree termination — branches L1 otherwise hides from dune runtest.
for n in ca cb; do
  other=$([ "$n" = ca ] && echo cb || echo ca)
  cat > ".ditz/issue-$n.yaml" <<YAML
id: $n
title: cycle $n
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
blocks:
- $other
blocked_by:
- $other
YAML
done
out="$("$BIN" deps --check 2>&1)"; check "deps --check flags cycle" 1 "$?"
contains "deps --check reports CYCLE" "CYCLE (mutually blocking)" "$out"
contains "deps --check --json cyclic_components" "cyclic_components" "$("$BIN" deps --check --json)"
tree="$("$BIN" deps ca 2>&1)"; check "deps on a cycle terminates" 0 "$?"
contains "deps tree marks cycle" "(cycle)" "$tree"
out="$("$BIN" deps no-such-id 2>&1)"; check "deps missing id errors" 1 "$?"

# --dot escapes quotes in titles
"$BIN" add 'evil "q" title' --id evilq --ids-only >/dev/null
contains "deps --dot escapes quotes" '\"q\"' "$("$BIN" deps --dot)"

# Step 4: import beads JSONL from stdin
printf '%s\n' \
  '{"id":"imp-1","title":"imported open","status":"open","priority":1,"issue_type":"bug"}' \
  '{"id":"imp-2","title":"imported closed","status":"closed","close_reason":"done deal","issue_type":"task"}' \
  | "$BIN" import - >/dev/null 2>&1
check "import from stdin" 0 "$?"
contains "imported issue present" '"status":"closed"' "$("$BIN" show imp-2 --json)"
contains "import maps close_reason to event" "done deal" "$("$BIN" show imp-2)"
contains "import maps open->unstarted" '"status":"unstarted"' "$("$BIN" show imp-1 --json)"
# idempotent re-import skips
out="$(printf '%s\n' '{"id":"imp-1","title":"imported open","status":"open"}' | "$BIN" import - 2>&1)"
contains "re-import is idempotent" "1 already present" "$out"
# unknown format rejected
out="$(echo '{}' | "$BIN" import - --format jira 2>&1)"; check "import unknown format rejected" 1 "$?"
# An id ditz can't store is RENAMED, not dropped: the issue survives and the
# reciprocal edge is rewritten to the new id. Renaming is lossless, so it is a
# note and the exit status stays 0.
imp_out="$(printf '%s\n' \
  '{"id":"okv","title":"valid one","status":"open"}' \
  '{"id":"bad.v","title":"invalid id","status":"open","dependencies":[{"issue_id":"bad.v","depends_on_id":"okv","type":"blocks"}]}' \
  | "$BIN" import - 2>&1)"; rc=$?
check "lossless rename import exits 0" 0 "$rc"
contains "invalid id renamed, not skipped" "renamed id 'bad.v' -> 'bad-v'" "$imp_out"
contains "renamed bead is present" '"title":"invalid id"' "$("$BIN" show bad-v --json)"
contains "original beads id kept in provenance" "beads_id=bad.v" "$("$BIN" show bad-v)"
contains "reciprocal edge follows the rename" '"blocks":["bad-v"]' "$("$BIN" show okv --json)"
# council-convergence regression: the pre-rename id must not survive anywhere in
# the graph (tracker has other fixtures, so check this leak specifically).
case "$("$BIN" deps --check 2>&1)" in *bad.v*) echo "FAIL: bad.v leaked into graph"; fail=1;; *) echo "ok: no bad.v leak in deps --check";; esac

# An id that renaming cannot rescue is still dropped -- and that is data loss,
# so it must warn AND exit non-zero. Its reciprocal edge must not leak either.
imp_out="$(printf '%s\n' \
  '{"id":"okw","title":"valid two","status":"open"}' \
  '{"id":"","title":"empty id","status":"open","dependencies":[{"issue_id":"","depends_on_id":"okw","type":"blocks"}]}' \
  | "$BIN" import - 2>&1)"; rc=$?
check "lossy import exits non-zero" 1 "$rc"
contains "lossy import says so" "Import INCOMPLETE" "$imp_out"
contains "unstorable id still dropped" "skipped invalid issue id" "$imp_out"
contains "dropped bead leaks no reciprocal edge" '"blocks":[]' "$("$BIN" show okw --json)"

# An edge to an id that will not exist after the import is dropped and warned:
# keeping it would leave `deps --check` calling the whole graph DANGLING.
imp_out="$(printf '%s\n' \
  '{"id":"dang-1","title":"real","status":"open","dependencies":[{"issue_id":"dang-1","depends_on_id":"ghost-1","type":"blocks"}]}' \
  | "$BIN" import - 2>&1)"; rc=$?
check "dangling endpoint exits non-zero" 1 "$rc"
contains "dangling endpoint warned" "dropped blocking edge to unknown id 'ghost-1'" "$imp_out"
contains "dangling endpoint not stored" '"blocked_by":[]' "$("$BIN" show dang-1 --json)"

# A rename onto an id an UNRELATED issue already holds must not swallow the
# incoming issue; re-importing the same issue must stay a benign skip.
"$BIN" import - >/dev/null 2>&1 <<'JSONL'
{"id":"occ-1","title":"the incumbent","status":"open"}
JSONL
imp_out="$(printf '%s\n' '{"id":"occ.1","title":"different issue","status":"open"}' | "$BIN" import - 2>&1)"; rc=$?
check "destination collision exits non-zero" 1 "$rc"
contains "destination collision warned" "an unrelated issue already holds that id" "$imp_out"
contains "incumbent untouched" '"title":"the incumbent"' "$("$BIN" show occ-1 --json)"
# ...whereas re-importing the same renamed issue is idempotent, not a collision
"$BIN" import - >/dev/null 2>&1 <<'JSONL'
{"id":"same.1","title":"mine","status":"open"}
JSONL
imp_out="$(printf '%s\n' '{"id":"same.1","title":"mine","status":"open"}' | "$BIN" import - 2>&1)"; rc=$?
check "same-issue re-import exits 0" 0 "$rc"
contains "same-issue re-import is a skip" "1 already present" "$imp_out"

# An edge whose far side is an already-present issue must be written on BOTH
# sides, or `deps --check` reports ONE-SIDED.
"$BIN" import - >/dev/null 2>&1 <<'JSONL'
{"id":"ep-1","title":"epic","status":"open"}
JSONL
imp_out="$("$BIN" import - 2>&1 <<'JSONL'
{"id":"ep-1","title":"epic","status":"open"}
{"id":"ep-kid","title":"child","status":"open","dependencies":[{"issue_id":"ep-kid","depends_on_id":"ep-1","type":"parent-child"}]}
JSONL
)"; rc=$?
check "completing an existing issue's edge exits 0" 0 "$rc"
contains "far side completed" '"blocked_by":["ep-kid"]' "$("$BIN" show ep-1 --json)"
# Scoped to this pair on purpose: the tracker also holds fixtures that are
# deliberately cyclic/dangling to exercise `deps --check` itself, so global
# cleanliness is not the assertion available here.
case "$("$BIN" deps --check 2>&1 | grep -E 'ep-1|ep-kid')" in
  *ONE-SIDED*|*DANGLING*) echo "FAIL: import left ep-1/ep-kid in an invalid state"; fail=1;;
  *) echo "ok: imported edge is valid on both sides";;
esac

# A save that fails must not leave an existing issue pointing at the issue that
# was never written. This needs a WRITE to fail while reads still work, so the
# issue dir is made unwritable -- a directory at the target path would instead
# be caught by the unreadable-issue guard below, never reaching the save. The
# discriminator is that no edge completion is even attempted: if the patch were
# queued before the save, it would be tried and reported here too.
if [ "$(id -u)" != "0" ]; then
  "$BIN" import - >/dev/null 2>&1 <<'JSONL'
{"id":"sf-existing","title":"incumbent","status":"open"}
JSONL
  chmod a-w .ditz
  imp_out="$(printf '%s\n' \
    '{"id":"sf-new","title":"cannot be written","status":"open","dependencies":[{"issue_id":"sf-new","depends_on_id":"sf-existing","type":"blocks"}]}' \
    | "$BIN" import - 2>&1)"; rc=$?
  chmod u+w .ditz
  check "failed save exits non-zero" 1 "$rc"
  contains "failed save is reported" "failed to save sf-new" "$imp_out"
  case "$imp_out" in
    *"failed to complete edges"*) echo "FAIL: edge completion was queued for a save that failed"; fail=1;;
    *) echo "ok: no edge completion queued for a failed save";;
  esac
  # ...and nothing about the unwritten issue reached the existing one. Checked
  # by id rather than by field name: the reciprocal of "sf-existing blocks
  # sf-new" lands in sf-existing's `blocks`, which is easy to misread.
  case "$("$BIN" show sf-existing --json)" in
    *sf-new*) echo "FAIL: existing issue points at the issue that was never written"; fail=1;;
    *) echo "ok: existing issue not pointed at the unwritten issue";;
  esac
else
  echo "ok: save-failure test skipped (running as root; permission bits do not apply)"
fi

# An issue whose file exists but cannot be read must not be overwritten by an
# import: "absent" and "unreadable" are different answers, and only one of them
# makes creating safe. A directory at the path is used rather than chmod so the
# test still fails the read when run as root.
mkdir -p .ditz/issue-ur-1.yaml
imp_out="$(printf '%s\n' '{"id":"ur-1","title":"replacement","status":"open"}' | "$BIN" import - 2>&1)"; rc=$?
check "unreadable existing issue exits non-zero" 1 "$rc"
contains "unreadable existing issue is refused" "refusing to overwrite it" "$imp_out"
[ -d .ditz/issue-ur-1.yaml ] || { echo "FAIL: import clobbered the unreadable issue"; fail=1; }
[ -d .ditz/issue-ur-1.yaml ] && echo "ok: unreadable issue left intact"
rmdir .ditz/issue-ur-1.yaml

# An issue cannot block itself: beads allows the record, `deps --check` calls
# it a CYCLE, so the importer must not write it.
imp_out="$(printf '%s\n' \
  '{"id":"self-1","title":"t","status":"open","dependencies":[{"issue_id":"self-1","depends_on_id":"self-1","type":"blocks"}]}' \
  | "$BIN" import - 2>&1)"; rc=$?
check "self-referential edge exits non-zero" 1 "$rc"
contains "self-referential edge warned" "dropped self-referential edge" "$imp_out"
contains "self-referential edge not stored" '"blocked_by":[]' "$("$BIN" show self-1 --json)"
case "$("$BIN" deps --check 2>&1 | grep 'self-1')" in *CYCLE*) echo "FAIL: import created a self-cycle"; fail=1;; *) echo "ok: no self-cycle created";; esac

# An edge naming an id that is NOT in this file must not attach itself to an
# unrelated issue that merely occupies the sanitized form of that id.
"$BIN" import - >/dev/null 2>&1 <<'JSONL'
{"id":"alias-y","title":"unrelated incumbent","status":"open"}
JSONL
imp_out="$(printf '%s\n' \
  '{"id":"alias-n","title":"new","status":"open","dependencies":[{"issue_id":"alias-n","depends_on_id":"alias.y","type":"blocks"}]}' \
  | "$BIN" import - 2>&1)"; rc=$?
check "aliasing endpoint exits non-zero" 1 "$rc"
contains "aliasing endpoint dropped" "dropped blocking edge to unknown id 'alias.y'" "$imp_out"
contains "unrelated incumbent not wired up" '"blocks":[]' "$("$BIN" show alias-y --json)"
# ...but an endpoint DOES resolve when the occupant proves it came from that
# beads id, which is the incremental-import case that must keep working.
"$BIN" import - >/dev/null 2>&1 <<'JSONL'
{"id":"prov.y","title":"imported earlier","status":"open"}
JSONL
imp_out="$(printf '%s\n' \
  '{"id":"prov-n","title":"new","status":"open","dependencies":[{"issue_id":"prov-n","depends_on_id":"prov.y","type":"blocks"}]}' \
  | "$BIN" import - 2>&1)"; rc=$?
check "vouched endpoint exits 0" 0 "$rc"
contains "vouched endpoint connects" '"blocked_by":["prov-y"]' "$("$BIN" show prov-n --json)"

# A field that is present but of the wrong type is data we were handed and
# dropped, so it warns; an absent field does not.
imp_out="$(printf '%s\n' \
  '{"id":"wt-1","title":"t","status":"open","acceptance_criteria":42}' \
  | "$BIN" import - 2>&1)"; rc=$?
check "wrong-typed field exits non-zero" 1 "$rc"
contains "wrong-typed field warned" "acceptance_criteria" "$imp_out"

# beads parent-child becomes a real blocking edge: child blocks parent, so the
# epic is not ready until its children close.
"$BIN" import - >/dev/null 2>&1 <<'JSONL'
{"id":"epic-p","title":"epic","status":"open"}
{"id":"kid-a","title":"child a","status":"open","acceptance_criteria":"the bar is met","dependencies":[{"issue_id":"kid-a","depends_on_id":"epic-p","type":"parent-child"}]}
JSONL
contains "child blocks its parent" '"blocks":["epic-p"]' "$("$BIN" show kid-a --json)"
contains "parent is blocked by its child" '"blocked_by":["kid-a"]' "$("$BIN" show epic-p --json)"
contains "acceptance_criteria folded into desc" "Acceptance: the bar is met" "$("$BIN" show kid-a)"

if [ "$fail" = 0 ]; then echo "All CLI smoke tests passed"; else echo "CLI smoke tests FAILED"; fi
exit "$fail"
