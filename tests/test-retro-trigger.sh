#!/usr/bin/env bash
# Functional test: task-completion.sh emits the retro-analyst spawn directive
# after a successful git push (the retro back-edge trigger).
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/core/hooks/task-completion.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { echo "  PASS: $1"; }
die()  { echo "  FAIL: $1"; fail=1; }

mkdir -p "$TMP/repo" && cd "$TMP/repo"
git init -q . && git config user.email t@t && git config user.name t
echo x > f && git add -A && git commit -qm "feat: x"

# 1. Successful push in a git repo -> retro directive
MSG=$(jq -n --arg cwd "$TMP/repo" \
  '{tool_name: "Bash", tool_input: {command: "git push"}, tool_result: {exit_code: "0"}, cwd: $cwd}' \
  | bash "$HOOK" | jq -r '.systemMessage // empty')
echo "$MSG" | grep -q "retro-analyst" && pass "push triggers retro-analyst directive" || die "no retro directive: $MSG"

# 2. Non-push command -> silent
OUT=$(jq -n --arg cwd "$TMP/repo" \
  '{tool_name: "Bash", tool_input: {command: "git status"}, tool_result: {exit_code: "0"}, cwd: $cwd}' \
  | bash "$HOOK")
[ -z "$OUT" ] && pass "non-push stays silent" || die "unexpected output: $OUT"

# 3. Failed push -> silent
OUT=$(jq -n --arg cwd "$TMP/repo" \
  '{tool_name: "Bash", tool_input: {command: "git push"}, tool_result: {exit_code: "1"}, cwd: $cwd}' \
  | bash "$HOOK")
[ -z "$OUT" ] && pass "failed push stays silent" || die "unexpected output on failed push: $OUT"

exit $fail
