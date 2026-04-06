#!/bin/bash
# PostToolUse hook: detects fixture drift after bench migrate
# PROJECT-AWARE: Uses project-detect.sh for dynamic bench/app/site detection

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // empty')

# Only match Bash tool with bench migrate commands
[ "$TOOL_NAME" = "Bash" ] || exit 0
echo "$COMMAND" | grep -qE 'bench\s+.*migrate' || exit 0
[ "$EXIT_CODE" = "0" ] || exit 0

# Skip if deploy agent set the skip flag
[ "$DEPLOY_AGENT_SKIP_MIGRATE_CHECK" = "1" ] && exit 0

# Source project detection library
LIB_DIR="$HOME/.claude/hooks/lib"
if [ -f "$LIB_DIR/project-detect.sh" ]; then
  source "$LIB_DIR/project-detect.sh"
fi

# Resolve bench root — use detected or fall back to config
BENCH="${PD_BENCH_ROOT:-$BENCH_ROOT}"
[ -z "$BENCH" ] && BENCH="$HOME/frappe-bench"

# Get site name dynamically
if type pd_get_site_name &>/dev/null; then
  SITE=$(pd_get_site_name)
else
  SITE="${FRAPPE_SITE:-erplocal.dev}"
fi

# Get custom apps dynamically
if type pd_get_custom_apps &>/dev/null; then
  APPS=$(pd_get_custom_apps)
else
  APPS="${CUSTOM_APPS:-}"
fi

DRIFT_FOUND=""

for app in $APPS; do
  APP_DIR="$BENCH/apps/$app"
  [ -d "$APP_DIR" ] || continue

  # Check if app has fixtures defined in hooks.py
  grep -q 'fixtures' "$APP_DIR/$app/hooks.py" 2>/dev/null || continue

  FIXTURE_DIR="$APP_DIR/$app/fixtures"
  [ -d "$FIXTURE_DIR" ] || continue

  # Export fixtures to temp dir and compare
  TEMP_DIR=$(mktemp -d)
  (cd "$BENCH" && bench --site "$SITE" export-fixtures --app "$app" --export-path "$TEMP_DIR" 2>/dev/null)

  if [ -d "$TEMP_DIR" ] && [ "$(ls -A "$TEMP_DIR" 2>/dev/null)" ]; then
    for fixture_file in "$TEMP_DIR"/*.json; do
      [ -f "$fixture_file" ] || continue
      fixture_name=$(basename "$fixture_file")
      existing="$FIXTURE_DIR/$fixture_name"

      if [ ! -f "$existing" ]; then
        DRIFT_FOUND="${DRIFT_FOUND}\n  $app: NEW fixture $fixture_name (exists in DB but not in repo)"
      elif ! diff -q "$fixture_file" "$existing" >/dev/null 2>&1; then
        DRIFT_FOUND="${DRIFT_FOUND}\n  $app: CHANGED $fixture_name (DB differs from repo)"
      fi
    done
  fi

  rm -rf "$TEMP_DIR"
done

if [ -n "$DRIFT_FOUND" ]; then
  echo "{\"systemMessage\": \"MANDATORY HOOK: Fixture drift detected after migrate:${DRIFT_FOUND}\nRun 'bench --site $SITE export-fixtures --app <app>' NOW, then commit the updated fixture files. Do not proceed until fixtures are synced.\"}"
fi

exit 0
