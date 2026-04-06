#!/bin/bash
# Stop hook: reminds about uncommitted changes and lint issues before declaring done
# This is a soft reminder — exit 0 always (don't block)
# PROJECT-AWARE: Uses project-detect.sh for dynamic bench/app detection
# Timeout: 15 seconds to prevent blocking on large worktree checks

exec 2>/dev/null
timeout 15 bash -c '

# Source project detection library
LIB_DIR="$HOME/.claude/hooks/lib"
if [ -f "$LIB_DIR/project-detect.sh" ]; then
  source "$LIB_DIR/project-detect.sh"
fi

BENCH="${PD_BENCH_ROOT:-${BENCH_ROOT:-$HOME/frappe-bench}}"

cd "$BENCH" 2>/dev/null || exit 0

# Get custom apps dynamically
if type pd_get_custom_apps &>/dev/null; then
  CUSTOM_APPS=$(pd_get_custom_apps)
else
  CUSTOM_APPS="${CUSTOM_APPS:-}"
fi

FRAMEWORK_APPS="frappe erpnext hrms insights payments india_compliance lms"

is_framework_app() {
  local app="$1"
  for fw in $FRAMEWORK_APPS; do
    [ "$app" = "$fw" ] && return 0
  done
  return 1
}

# Check each app for uncommitted changes
DIRTY_APPS=""
for app_dir in apps/*/; do
  if [ -d "$app_dir/.git" ]; then
    app_name=$(basename "$app_dir")
    if [ -n "$(git -C "$app_dir" status --porcelain 2>/dev/null)" ]; then
      DIRTY_APPS="$DIRTY_APPS $app_name"
    fi
  fi
done

if [ -n "$DIRTY_APPS" ]; then
  echo "REMINDER: Uncommitted changes detected in:$DIRTY_APPS"
  echo "Consider committing before running bench migrate."

  CUSTOM_DIRTY=""
  for app in $DIRTY_APPS; do
    is_framework_app "$app" || CUSTOM_DIRTY="$CUSTOM_DIRTY $app"
  done
  if [ -n "$CUSTOM_DIRTY" ]; then
    echo "TIP: Run /deploy to commit, push, tag, release, migrate, and test."
  fi
fi

# --- Deploy check ---
for app in $DIRTY_APPS; do
  is_framework_app "$app" && continue
  RECENT_CODE_COMMIT=$(git -C "$BENCH/apps/$app" log --since="30 minutes ago" --diff-filter=M --name-only --pretty=format:"" -- "*.py" "*.js" "*.ts" 2>/dev/null | head -1)
  if [ -n "$RECENT_CODE_COMMIT" ]; then
    DEPLOY_LOG=$(find /tmp -name "deploy-manifest-*" -mmin -30 2>/dev/null | head -1)
    DEPLOY_HISTORY_RECENT=$(tail -1 "$BENCH/logs/deploy-history.log" 2>/dev/null | grep "$(date +%Y-%m-%d)" | grep "$app" || true)
    if [ -z "$DEPLOY_LOG" ] && [ -z "$DEPLOY_HISTORY_RECENT" ]; then
      echo "WARNING: $app has recent code commits but /deploy was NOT run."
      echo "  Run /deploy to build, migrate, test, and update changelog."
    fi
  fi
done

# --- Lint status check ---
LINT_ISSUES=""
for app_dir in "$BENCH"/apps/*/; do
  [ -d "$app_dir" ] || continue
  app_name=$(basename "$app_dir")
  is_framework_app "$app_name" && continue

  if [ -f "$app_dir/pyproject.toml" ] && grep -q "\[tool\.ruff\]" "$app_dir/pyproject.toml" 2>/dev/null; then
    exclude_args=""
    for subdir in "$app_dir"/*/; do
      [ -f "$subdir/package.json" ] && exclude_args="$exclude_args --exclude $(basename "$subdir")/**"
    done
    OUT=$(cd "$app_dir" && ruff check . $exclude_args 2>&1)
    [ $? -ne 0 ] && LINT_ISSUES="${LINT_ISSUES}\n  ${app_name} (ruff): $(echo "$OUT" | tail -1)"
  fi

  for subdir in "$app_dir"/*/; do
    [ -d "$subdir" ] || continue
    subdir_name=$(basename "$subdir")
    if [ -f "$subdir/.oxlintrc.json" ] && [ -f "$subdir/package.json" ]; then
      OUT=$(cd "$subdir" && npx oxlint -c .oxlintrc.json . --deny-warnings 2>&1)
      [ $? -ne 0 ] && LINT_ISSUES="${LINT_ISSUES}\n  ${app_name}/${subdir_name} (oxlint): $(echo "$OUT" | grep "Found" | tail -1)"
    fi
  done
done

if [ -n "$LINT_ISSUES" ]; then
  echo ""
  echo "WARNING: Outstanding lint issues detected:"
  echo -e "$LINT_ISSUES"
  echo "Fix these before committing — the commit gate will block you."
fi

# --- Session handoff ---
echo ""
echo "{\"systemMessage\": \"MANDATORY HOOK: Session ending. Save a project memory summarizing: (1) what was worked on this session, (2) what is left to do if any tasks are incomplete, (3) any blockers encountered.\"}"

exit 0
'
exit 0
