#!/bin/bash
# pre-gates.sh — deterministic pre-gates that run BEFORE any LLM reviewer.
# Rationale: deterministic filters ahead of LLM judges (Meta ACH: 0.79→0.95
# precision behind a deterministic pre-filter). A commit that fails these
# never reaches (or pays for) an LLM review.
#
# Usage: pre-gates.sh <repo_dir> [diff_range]
# Exit 0 = all gates green. Exit 1 = at least one gate failed (failures on stdout).
# Fast checks only (<60s budget) — full test execution belongs to the reviewer
# agents themselves (EXECUTION-REQUIRED mandate).

set -u
REPO_DIR="${1:?usage: pre-gates.sh <repo_dir> [diff_range]}"
RANGE="${2:-HEAD~1..HEAD}"

LOG_DIR="$HOME/.claude/pipeline/telemetry"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pre-gates.log"

log() { echo "[pre-gates] $*"; }

cd "$REPO_DIR" 2>/dev/null || { log "FAIL cannot cd to $REPO_DIR"; exit 1; }
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { log "not a git repo — skipping"; exit 0; }
cd "$GIT_ROOT" || exit 1

CHANGED=$(git diff --name-only "$RANGE" 2>/dev/null)
[ -z "$CHANGED" ] && { log "no changed files in $RANGE — green"; exit 0; }

# Detect project type (shared library; falls back to generic)
PD_LIB="$HOME/.claude/hooks/lib/project-detect.sh"
APP_TYPE="generic"
if [ -f "$PD_LIB" ]; then
  PD_PROJECT_ROOT="$GIT_ROOT"
  # shellcheck disable=SC1090
  source "$PD_LIB"
  APP_TYPE="${PD_PROJECT_TYPE:-generic}"
fi

FAILURES=0
RESULTS=""

record() { # record <gate> <status> <detail>
  RESULTS="${RESULTS}${1}: ${2}${3:+ — $3}\n"
  [ "$2" = "FAIL" ] && FAILURES=$((FAILURES + 1))
  log "$1: $2${3:+ — $3}"
}

# --- Gate: ruff on changed Python files (frappe + python + generic) ---
PY_CHANGED=$(echo "$CHANGED" | grep -E '\.py$' || true)
if [ -n "$PY_CHANGED" ] && command -v ruff >/dev/null 2>&1; then
  # Only lint files that still exist (renames/deletions)
  PY_EXISTING=$(echo "$PY_CHANGED" | while read -r f; do [ -f "$f" ] && echo "$f"; done)
  if [ -n "$PY_EXISTING" ]; then
    RUFF_OUT=$(echo "$PY_EXISTING" | xargs ruff check --quiet 2>&1)
    if [ $? -eq 0 ]; then
      record "ruff" "PASS"
    else
      record "ruff" "FAIL" "$(echo "$RUFF_OUT" | head -5 | tr '\n' '; ')"
    fi
  fi
fi

# --- Gate: DocType JSON schema validation (frappe) ---
DOCTYPE_CHANGED=$(echo "$CHANGED" | grep -E 'doctype/.*\.json$' || true)
if [ -n "$DOCTYPE_CHANGED" ]; then
  DT_ERRS=""
  while read -r f; do
    [ -f "$f" ] || continue
    ERR=$(python3 - "$f" <<'PYEOF' 2>&1
import json, sys
path = sys.argv[1]
try:
    with open(path) as fh:
        doc = json.load(fh)
except Exception as e:
    print(f"{path}: invalid JSON — {e}")
    sys.exit(1)
if doc.get("doctype") != "DocType":
    sys.exit(0)  # child/other json — parse-only check
problems = []
if not doc.get("name"):
    problems.append("missing name")
fieldnames = [f.get("fieldname") for f in doc.get("fields", []) if isinstance(f, dict)]
dupes = {x for x in fieldnames if x and fieldnames.count(x) > 1}
if dupes:
    problems.append(f"duplicate fieldnames: {sorted(dupes)}")
for fld in doc.get("fields", []):
    if isinstance(fld, dict) and fld.get("fieldtype") in ("Link", "Table", "Table MultiSelect") and not fld.get("options"):
        problems.append(f"{fld.get('fieldname')}: {fld.get('fieldtype')} without options")
if problems:
    print(f"{path}: " + "; ".join(problems))
    sys.exit(1)
PYEOF
)
    [ $? -ne 0 ] && DT_ERRS="${DT_ERRS}${ERR}; "
  done <<< "$DOCTYPE_CHANGED"
  if [ -z "$DT_ERRS" ]; then
    record "doctype-schema" "PASS"
  else
    record "doctype-schema" "FAIL" "$DT_ERRS"
  fi
fi

# --- Gate: biome on changed JS/TS files (node-family stacks) ---
JS_CHANGED=$(echo "$CHANGED" | grep -E '\.(ts|tsx|js|jsx)$' || true)
case "$APP_TYPE" in
  react-ts|monorepo|electron|node)
    if [ -n "$JS_CHANGED" ] && command -v bunx >/dev/null 2>&1 && \
       { [ -f "biome.json" ] || [ -f "biome.jsonc" ]; }; then
      JS_EXISTING=$(echo "$JS_CHANGED" | while read -r f; do [ -f "$f" ] && echo "$f"; done)
      if [ -n "$JS_EXISTING" ]; then
        BIOME_OUT=$(echo "$JS_EXISTING" | timeout 60 xargs bunx biome check 2>&1)
        if [ $? -eq 0 ]; then
          record "biome" "PASS"
        else
          record "biome" "FAIL" "$(echo "$BIOME_OUT" | grep -E '^\S+\.(ts|tsx|js|jsx)' | head -5 | tr '\n' '; ')"
        fi
      fi
    fi
    ;;
esac

# --- Gate: Frappe bench checks (opt-in via PRE_GATES_BENCH=1 — slow) ---
# migrate + app-scoped tests are the strongest Frappe oracle; they need a
# bench context and real time, so they're opt-in here. When not opted in,
# the frappe-reviewer's EXECUTION-REQUIRED mandate runs them instead.
if [ "${PRE_GATES_BENCH:-0}" = "1" ] && [ -f "$GIT_ROOT/hooks.py" -o -n "$(ls "$GIT_ROOT"/*/hooks.py 2>/dev/null)" ]; then
  BENCH_ROOT=""
  CHECK="$GIT_ROOT"
  while [ "$CHECK" != "/" ]; do
    [ -f "$CHECK/sites/common_site_config.json" ] && { BENCH_ROOT="$CHECK"; break; }
    CHECK=$(dirname "$CHECK")
  done
  if [ -n "$BENCH_ROOT" ] && [ -f "$BENCH_ROOT/sites/currentsite.txt" ]; then
    SITE=$(cat "$BENCH_ROOT/sites/currentsite.txt")
    APP_NAME=$(basename "$GIT_ROOT")
    if (cd "$BENCH_ROOT" && timeout 180 bench --site "$SITE" migrate) >/dev/null 2>&1; then
      record "bench-migrate" "PASS"
    else
      record "bench-migrate" "FAIL" "migrate failed for site $SITE — schema changes not applied"
    fi
    TEST_OUT=$(cd "$BENCH_ROOT" && timeout 600 bench --site "$SITE" run-tests --app "$APP_NAME" 2>&1)
    if [ $? -eq 0 ]; then
      record "bench-tests" "PASS"
    else
      record "bench-tests" "FAIL" "$(echo "$TEST_OUT" | grep -E 'FAIL|Error' | head -3 | tr '\n' '; ')"
    fi
  else
    record "bench-context" "PASS" "no bench root/site found — skipped"
  fi
fi

# --- Gate: shell syntax on changed hook/scripts (pipeline repo itself) ---
SH_CHANGED=$(echo "$CHANGED" | grep -E '\.sh$' || true)
if [ -n "$SH_CHANGED" ]; then
  SH_ERRS=""
  while read -r f; do
    [ -f "$f" ] || continue
    ERR=$(bash -n "$f" 2>&1) || SH_ERRS="${SH_ERRS}${f}: ${ERR}; "
  done <<< "$SH_CHANGED"
  if [ -z "$SH_ERRS" ]; then
    record "bash-syntax" "PASS"
  else
    record "bash-syntax" "FAIL" "$SH_ERRS"
  fi
fi

# --- Gate: no generated backup artifacts in the commit ---
# (retro learning 2026-07-20: a settings.json.tmpl.bak-<epoch> swept into a
# feat commit — this class of mistake is deterministic to catch)
BAK_CHANGED=$(echo "$CHANGED" | grep -E '\.bak(-[0-9]+)?$|\.orig$|~$' || true)
if [ -n "$BAK_CHANGED" ]; then
  record "no-backup-files" "FAIL" "generated backup artifacts committed: $(echo "$BAK_CHANGED" | tr '\n' ' ')"
fi

# --- Summary ---
echo "----"
printf "%b" "$RESULTS"
echo "[pre-gates] $(date -u +%FT%TZ) repo=$GIT_ROOT type=$APP_TYPE failures=$FAILURES" >> "$LOG_FILE"

if [ "$FAILURES" -gt 0 ]; then
  log "RESULT: FAIL ($FAILURES gate(s)) — fix deterministically before any LLM review"
  exit 1
fi
log "RESULT: PASS"
exit 0
