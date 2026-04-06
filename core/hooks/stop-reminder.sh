#!/bin/bash
# Stop hook: reminds about uncommitted changes and lint issues before declaring done
# This is a soft reminder — exit 0 always (don't block)
# PROJECT-AWARE: Uses project-detect.sh for dynamic detection
# Timeout: 15 seconds to prevent blocking on large worktree checks

# Wrap main logic in timeout
exec 2>/dev/null
timeout 15 bash -c '

# Source project detection library
LIB_DIR="${PIPELINE_HOOKS_DIR:-$HOME/.claude/hooks}/lib"
if [ -f "$LIB_DIR/project-detect.sh" ]; then
  source "$LIB_DIR/project-detect.sh"
fi

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
[ -n "$GIT_ROOT" ] || exit 0

# --- Generic git repo: check for uncommitted changes ---
DIRTY_APPS=""

if [ "${PD_IS_FRAPPE_BENCH:-0}" = "1" ] && [ -n "${PD_BENCH_ROOT:-}" ]; then
  # Frappe bench: check each app for uncommitted changes
  cd "$PD_BENCH_ROOT" 2>/dev/null || exit 0

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
  fi

  # Bench-specific deploy check
  if type pd_get_custom_apps &>/dev/null; then
    CUSTOM_APPS=$(pd_get_custom_apps)
  else
    CUSTOM_APPS=""
  fi

  # Framework apps to skip for lint/deploy checks
  FRAMEWORK_APPS="frappe erpnext hrms insights payments india_compliance lms"
  is_framework_app() {
    local app="$1"
    for fw in $FRAMEWORK_APPS; do
      [ "$app" = "$fw" ] && return 0
    done
    return 1
  }

  # --- Lint status check (soft warning) — auto-discovers project types ---
  LINT_ISSUES=""
  for app_dir in "$PD_BENCH_ROOT"/apps/*/; do
    [ -d "$app_dir" ] || continue
    app_name=$(basename "$app_dir")
    is_framework_app "$app_name" && continue

    # Python: check if pyproject.toml has ruff config
    if [ -f "$app_dir/pyproject.toml" ] && grep -q "\[tool\.ruff\]" "$app_dir/pyproject.toml" 2>/dev/null; then
      exclude_args=""
      for subdir in "$app_dir"/*/; do
        [ -f "$subdir/package.json" ] && exclude_args="$exclude_args --exclude $(basename "$subdir")/**"
      done
      OUT=$(cd "$app_dir" && ruff check . $exclude_args 2>&1)
      [ $? -ne 0 ] && LINT_ISSUES="${LINT_ISSUES}\n  ${app_name} (ruff): $(echo "$OUT" | tail -1)"
    fi

    # Frontend subdirs: check for oxlint
    for subdir in "$app_dir"/*/; do
      [ -d "$subdir" ] || continue
      subdir_name=$(basename "$subdir")
      if [ -f "$subdir/.oxlintrc.json" ] && [ -f "$subdir/package.json" ]; then
        OUT=$(cd "$subdir" && npx oxlint -c .oxlintrc.json . --deny-warnings 2>&1)
        [ $? -ne 0 ] && LINT_ISSUES="${LINT_ISSUES}\n  ${app_name}/${subdir_name} (oxlint): $(echo "$OUT" | grep "Found" | tail -1)"
      fi
    done

    # Kotlin: check for detekt
    if [ -f "$app_dir/build.gradle.kts" ] && [ -f "$app_dir/detekt.yml" ]; then
      OUT=$(cd "$app_dir" && ./gradlew detekt 2>&1)
      [ $? -ne 0 ] && LINT_ISSUES="${LINT_ISSUES}\n  ${app_name} (detekt): $(echo "$OUT" | grep -i "error\|failure" | tail -1)"
    fi
  done

  if [ -n "$LINT_ISSUES" ]; then
    echo ""
    echo "WARNING: Outstanding lint issues detected:"
    echo -e "$LINT_ISSUES"
    echo "Fix these before committing -- the commit gate will block you."
  fi

else
  # Non-bench: simple git repo check
  if [ -n "$(git -C "$GIT_ROOT" status --porcelain 2>/dev/null)" ]; then
    DIRTY_COUNT=$(git -C "$GIT_ROOT" status --porcelain 2>/dev/null | wc -l)
    echo "REMINDER: $DIRTY_COUNT uncommitted changes in $(basename "$GIT_ROOT")."
    echo "Consider committing your work."
  fi

  # Run lint check if pyproject.toml with ruff exists
  if [ -f "$GIT_ROOT/pyproject.toml" ] && grep -q "\[tool\.ruff\]" "$GIT_ROOT/pyproject.toml" 2>/dev/null; then
    OUT=$(cd "$GIT_ROOT" && ruff check . 2>&1)
    if [ $? -ne 0 ]; then
      echo ""
      echo "WARNING: Lint issues detected:"
      echo "$(echo "$OUT" | tail -3)"
    fi
  fi
fi

# --- Worktree checks (generic, not bench-specific) ---
if [ -n "$GIT_ROOT" ]; then
  STALE_WORKTREES=""
  while IFS= read -r wt_line; do
    wt_path=$(echo "$wt_line" | awk "{print \$1}")
    [ "$wt_path" = "$GIT_ROOT" ] && continue
    [ -d "$wt_path" ] || continue

    wt_branch=$(git -C "$wt_path" branch --show-current 2>/dev/null)
    [ -z "$wt_branch" ] && continue

    MAIN_BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null)
    IS_MERGED=$(git -C "$GIT_ROOT" branch --merged "$MAIN_BRANCH" 2>/dev/null | grep -w "$wt_branch")

    if [ -n "$IS_MERGED" ]; then
      STALE_WORKTREES="${STALE_WORKTREES}\n  $(basename "$GIT_ROOT")/$wt_branch: MERGED (safe to remove: git worktree remove $wt_path)"
    else
      LAST_COMMIT_TS=$(git -C "$wt_path" log -1 --format="%ct" 2>/dev/null || echo 0)
      NOW_TS=$(date +%s)
      AGE_DAYS=$(( (NOW_TS - LAST_COMMIT_TS) / 86400 ))
      if [ "$AGE_DAYS" -gt 14 ]; then
        STALE_WORKTREES="${STALE_WORKTREES}\n  $(basename "$GIT_ROOT")/$wt_branch: ${AGE_DAYS} days old"
      fi
    fi
  done < <(git -C "$GIT_ROOT" worktree list 2>/dev/null)

  if [ -n "$STALE_WORKTREES" ]; then
    echo ""
    echo "STALE WORKTREES detected:"
    echo -e "$STALE_WORKTREES"
    echo "TIP: Remove merged worktrees with '\''git worktree remove <path>'\''"
  fi
fi

# --- Session handoff notes ---
echo ""
echo "{\"systemMessage\": \"MANDATORY HOOK: Session ending. Save a project memory summarizing: (1) what was worked on this session, (2) what is left to do if any tasks are incomplete, (3) any blockers encountered. Save to memory file: session_handoff.md with type: project.\"}"

exit 0
'
exit 0
