#!/bin/bash
# PreToolUse hook: blocks git commit if linters fail
# Auto-detects project type from marker files — no hardcoded app names
# Exit 0 = allow, Exit 2 = block

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

ERRORS=""

# --- Helpers ---

find_git_root() {
  local dir="$1"
  # Use git rev-parse which handles worktrees (where .git is a file, not a dir)
  (cd "$dir" && git rev-parse --show-toplevel 2>/dev/null) && return 0
  return 1
}

run_python_lint() {
  local project_dir="$1"
  local app_name
  app_name=$(basename "$project_dir")

  # Check if pyproject.toml has ruff config
  [ -f "$project_dir/pyproject.toml" ] || return 0
  grep -q '\[tool\.ruff\]' "$project_dir/pyproject.toml" 2>/dev/null || return 0

  # Build exclude flags for frontend subdirs (pos/, bazaar/, node_modules/, etc.)
  local exclude_args=""
  for subdir in "$project_dir"/*/; do
    [ -f "$subdir/package.json" ] && exclude_args="$exclude_args --exclude $(basename "$subdir")/**"
  done

  local OUT
  OUT=$(cd "$project_dir" && ruff check . $exclude_args 2>&1)
  if [ $? -ne 0 ]; then
    ERRORS="${ERRORS}\n--- ${app_name^^} RUFF FAILED ---\n${OUT}\n"
  fi
}

run_frontend_lint() {
  local frontend_dir="$1"
  local frontend_name
  frontend_name=$(basename "$frontend_dir")
  local parent_name
  parent_name=$(basename "$(dirname "$frontend_dir")")
  local label="${parent_name}/${frontend_name}"

  # Must have tsconfig.json to be a TS frontend
  [ -f "$frontend_dir/tsconfig.json" ] || return 0
  # Must have package.json
  [ -f "$frontend_dir/package.json" ] || return 0

  # TypeScript check
  if [ -f "$frontend_dir/tsconfig.json" ]; then
    local OUT
    OUT=$(cd "$frontend_dir" && npx tsc --noEmit 2>&1)
    if [ $? -ne 0 ]; then
      ERRORS="${ERRORS}\n--- ${label^^} TYPECHECK FAILED ---\n$(echo "$OUT" | tail -15)\n"
    fi
  fi

  # oxlint (if .oxlintrc.json exists)
  if [ -f "$frontend_dir/.oxlintrc.json" ]; then
    OUT=$(cd "$frontend_dir" && npx oxlint -c .oxlintrc.json . --deny-warnings 2>&1)
    if [ $? -ne 0 ]; then
      ERRORS="${ERRORS}\n--- ${label^^} OXLINT FAILED ---\n$(echo "$OUT" | tail -15)\n"
    fi
  fi

  # eslint (if eslint config exists)
  if [ -f "$frontend_dir/eslint.config.js" ] || [ -f "$frontend_dir/eslint.config.mjs" ] || [ -f "$frontend_dir/.eslintrc.js" ] || [ -f "$frontend_dir/.eslintrc.json" ]; then
    OUT=$(cd "$frontend_dir" && npx eslint . 2>&1)
    if [ $? -ne 0 ]; then
      ERRORS="${ERRORS}\n--- ${label^^} ESLINT FAILED ---\n$(echo "$OUT" | tail -15)\n"
    fi
  fi

  # biome (if biome.json exists)
  if [ -f "$frontend_dir/biome.json" ]; then
    OUT=$(cd "$frontend_dir" && npx biome format . 2>&1)
    if [ $? -ne 0 ]; then
      ERRORS="${ERRORS}\n--- ${label^^} FORMAT FAILED ---\n$(echo "$OUT" | tail -15)\n"
    fi
  fi
}

run_kotlin_lint() {
  local project_dir="$1"
  local app_name
  app_name=$(basename "$project_dir")

  # Must have build.gradle.kts and detekt config
  [ -f "$project_dir/build.gradle.kts" ] || return 0
  [ -f "$project_dir/detekt.yml" ] || [ -d "$project_dir/config/detekt" ] || return 0

  local OUT
  OUT=$(cd "$project_dir" && ./gradlew detekt 2>&1)
  if [ $? -ne 0 ]; then
    ERRORS="${ERRORS}\n--- ${app_name^^} DETEKT FAILED ---\n$(echo "$OUT" | tail -15)\n"
  fi
}

run_js_lint() {
  local project_dir="$1"
  local app_name
  app_name=$(basename "$project_dir")

  # Check for staged .js files
  local CHANGED_JS
  CHANGED_JS=$(cd "$project_dir" && git diff --cached --name-only 2>/dev/null | grep '\.js$' || true)
  if [ -n "$CHANGED_JS" ]; then
    # Only lint if oxlint is available
    if command -v npx &>/dev/null; then
      local OUT
      OUT=$(cd "$project_dir" && echo "$CHANGED_JS" | xargs npx oxlint 2>&1)
      if [ $? -ne 0 ]; then
        ERRORS="${ERRORS}\n--- ${app_name^^} OXLINT FAILED ---\n${OUT}\n"
      fi
    fi
  fi
}

# --- Main: find git root and run appropriate checks ---

GIT_ROOT=$(find_git_root "$CWD")
[ -z "$GIT_ROOT" ] && exit 0

# --- Monorepo detection (turbo/bun at root) ---
if { [ -f "$GIT_ROOT/turbo.json" ] || [ -f "$GIT_ROOT/turbo.jsonc" ]; } && [ -f "$GIT_ROOT/bun.lock" ]; then
  # Bun + Turbo monorepo — use project-level commands
  if [ -f "$GIT_ROOT/biome.json" ] || [ -f "$GIT_ROOT/biome.jsonc" ]; then
    OUT=$(cd "$GIT_ROOT" && bun run lint 2>&1)
    if [ $? -ne 0 ]; then
      ERRORS="${ERRORS}\n--- MONOREPO LINT FAILED ---\n$(echo "$OUT" | tail -20)\n"
    fi
  fi

  # Typecheck via turbo
  OUT=$(cd "$GIT_ROOT" && bun run typecheck 2>&1)
  if [ $? -ne 0 ]; then
    ERRORS="${ERRORS}\n--- MONOREPO TYPECHECK FAILED ---\n$(echo "$OUT" | tail -20)\n"
  fi
else
  # --- Standard project detection (non-monorepo) ---

  # Run Python lint on git root
  run_python_lint "$GIT_ROOT"

  # Run Kotlin lint on git root
  run_kotlin_lint "$GIT_ROOT"

  # Run JS lint on git root (generic — works for any project with .js files)
  run_js_lint "$GIT_ROOT"

  # Auto-discover frontend subdirs (any subdir with tsconfig.json + package.json)
  for subdir in "$GIT_ROOT"/*/; do
    [ -d "$subdir" ] || continue
    if [ -f "$subdir/tsconfig.json" ] && [ -f "$subdir/package.json" ]; then
      run_frontend_lint "$subdir"
    fi
  done
fi

# --- Anti-pattern detection (advisory — warns but does not block) ---
if [ -n "$GIT_ROOT" ]; then
  STAGED_PY=$(cd "$GIT_ROOT" && git diff --cached --name-only 2>/dev/null | grep '\.py$' || true)
  if [ -n "$STAGED_PY" ]; then
    DB_WARNINGS=""
    while IFS= read -r pyfile; do
      [ -z "$pyfile" ] && continue
      [ -f "$GIT_ROOT/$pyfile" ] || continue
      # Find DB calls and check if they're inside loops (within 5 lines above)
      # Generic ORM patterns: .get(), .filter(), .query(), .execute(), .fetchall()
      while IFS=: read -r lineno _; do
        [ -z "$lineno" ] && continue
        start=$((lineno > 5 ? lineno - 5 : 1))
        context=$(sed -n "${start},${lineno}p" "$GIT_ROOT/$pyfile" 2>/dev/null)
        if echo "$context" | grep -qE '^\s*(for|while)\b'; then
          DB_WARNINGS="${DB_WARNINGS}\n  $pyfile:$lineno -- DB call inside loop"
        fi
      done < <(grep -nE '(frappe\.(get_doc|get_all|db\.get_value|db\.sql)|\.objects\.(get|filter|all)|\.query\(|\.execute\()\(' "$GIT_ROOT/$pyfile" 2>/dev/null | cut -d: -f1 | while read ln; do echo "$ln:"; done)
    done <<< "$STAGED_PY"
    if [ -n "$DB_WARNINGS" ]; then
      echo ""
      echo "WARNING: Possible DB calls inside loops (advisory):"
      echo -e "$DB_WARNINGS"
      echo "Consider using bulk queries instead."
    fi
  fi
fi

# --- Verdict ---
if [ -n "$ERRORS" ]; then
  echo "=========================================="
  echo "  COMMIT BLOCKED -- quality gate failures"
  echo "=========================================="
  echo -e "$ERRORS"
  echo "Fix all issues, then try committing again."
  exit 2
fi

echo "All quality gates passed."
exit 0
