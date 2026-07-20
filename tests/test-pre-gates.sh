#!/usr/bin/env bash
# Functional test for lib/pre-gates.sh — deterministic pre-gates that run
# before any LLM reviewer. Builds throwaway git repos with known-bad and
# known-good commits and asserts the gate verdict.
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATES="$REPO_DIR/core/hooks/lib/pre-gates.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { echo "  PASS: $1"; }
die()  { echo "  FAIL: $1"; fail=1; }

mkrepo() { # $1 dir
  mkdir -p "$1" && cd "$1" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo base > base.txt && git add -A && git commit -qm "base"
}

# 1. Bad shell syntax in the commit -> FAIL
mkrepo "$TMP/r1"
printf '#!/bin/bash\nif [ x; then echo broken\n' > bad.sh
git add -A && git commit -qm "add bad shell"
if bash "$GATES" "$TMP/r1" >/dev/null 2>&1; then
  die "bad shell syntax should fail the gate"
else
  pass "bad shell syntax fails the gate"
fi

# 2. Clean shell in the commit -> PASS
mkrepo "$TMP/r2"
printf '#!/bin/bash\necho ok\n' > good.sh
git add -A && git commit -qm "add good shell"
if bash "$GATES" "$TMP/r2" >/dev/null 2>&1; then
  pass "clean shell passes the gate"
else
  die "clean shell should pass the gate"
fi

# 3. Invalid DocType JSON -> FAIL
mkrepo "$TMP/r3"
mkdir -p app/doctype/thing
printf '{"doctype": "DocType", "name": "Thing", "fields": [{"fieldname": "a", "fieldtype": "Link"}]}' \
  > app/doctype/thing/thing.json
git add -A && git commit -qm "doctype with Link missing options"
if bash "$GATES" "$TMP/r3" >/dev/null 2>&1; then
  die "Link field without options should fail doctype-schema gate"
else
  pass "Link field without options fails doctype-schema gate"
fi

# 4. Valid DocType JSON -> PASS
mkrepo "$TMP/r4"
mkdir -p app/doctype/thing
printf '{"doctype": "DocType", "name": "Thing", "fields": [{"fieldname": "a", "fieldtype": "Link", "options": "Customer"}]}' \
  > app/doctype/thing/thing.json
git add -A && git commit -qm "valid doctype"
if bash "$GATES" "$TMP/r4" >/dev/null 2>&1; then
  pass "valid doctype passes the gate"
else
  die "valid doctype should pass the gate"
fi

# 5. Ruff gate (only when ruff is installed)
if command -v ruff >/dev/null 2>&1; then
  mkrepo "$TMP/r5"
  printf 'import os\nimport sys\n\nx=  1\ndef f( ):\n    return undefined_name\n' > bad.py
  git add -A && git commit -qm "bad python"
  if bash "$GATES" "$TMP/r5" >/dev/null 2>&1; then
    die "ruff-failing python should fail the gate"
  else
    pass "ruff-failing python fails the gate"
  fi
else
  echo "  SKIP: ruff not installed"
fi

# 5b. Generated backup artifact in the commit -> FAIL
mkrepo "$TMP/r5b"
echo "stale" > "config.tmpl.bak-1784167796"
git add -A && git commit -qm "feat: sweep with backup file"
if bash "$GATES" "$TMP/r5b" >/dev/null 2>&1; then
  die "committed .bak-<epoch> artifact should fail the gate"
else
  pass "committed backup artifact fails the gate"
fi

# 6. No changed files of interest -> PASS (doesn't block unrelated commits)
mkrepo "$TMP/r6"
echo "notes" > notes.md
git add -A && git commit -qm "docs only"
if bash "$GATES" "$TMP/r6" >/dev/null 2>&1; then
  pass "docs-only commit passes the gate"
else
  die "docs-only commit should pass"
fi

exit $fail
