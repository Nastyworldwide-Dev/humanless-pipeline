#!/bin/bash
# UserPromptSubmit hook: detects ambiguous requirements and suggests clarification
# Watches for vague language that could lead to incorrect implementation
# Exit 0 = allow (always allows, emits systemMessage when ambiguity detected)

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

[ -z "$PROMPT" ] && exit 0

# Skip short prompts (likely commands or simple questions)
WORD_COUNT=$(echo "$PROMPT" | wc -w)
[ "$WORD_COUNT" -lt 10 ] && exit 0

# Detect vague/ambiguous language patterns — count OCCURRENCES via grep -o
# (grep -c counts lines, so a single-line prompt could never exceed 1 and the
# vague branch never fired; also no `|| echo 0`, which double-printed "0\n0")
VAGUE_COUNT=$(echo "$PROMPT" | grep -oiE '(make it better|improve|optimize|clean up|fix it|make it work|something like|sort of|kind of|maybe|probably|etc\.)' | wc -l)

# Detect implementation-shaped prompts (candidates for the spec compiler)
IMPL_COUNT=$(echo "$PROMPT" | grep -oiE '(\bfix\b|\badd\b|\bimplement\b|\bcreate\b|\bbuild\b|\bupdate\b|\bchange\b|\brefactor\b|\bmigrate\b)' | wc -l)

if [ "$VAGUE_COUNT" -gt 1 ]; then
  if [ "${PIPELINE_AUTONOMOUS:-0}" = "1" ]; then
    cat <<EOF
{"systemMessage": "This request contains ambiguous language and no user is present (PIPELINE_AUTONOMOUS=1). MANDATORY: run /grill-me Autonomous Mode BEFORE implementing — self-interrogate against repo/wiki/git history, write .claude/plans/clarify-record.md with RESOLVED/ASSUMED/BLOCKER states and a 'BLOCKERS: n' line. A BLOCKER parks the task; never guess."}
EOF
  else
    cat <<EOF
{"systemMessage": "SPEC COMPILER: this request is ambiguous. Before implementing, restate it back to the user as a compact structured spec — GOAL (one sentence), ACCEPTANCE (2-4 checkable criteria), OUT OF SCOPE (what you will NOT touch), SUSPECTED FILES (from a quick scan) — and ask for a one-line confirm or correction. Do NOT interrogate with open questions unless the spec genuinely cannot be drafted (then use /grill-me). Do NOT start editing before the confirm."}
EOF
  fi
elif [ "$IMPL_COUNT" -ge 1 ] && [ "$WORD_COUNT" -ge 25 ] && [ "${PIPELINE_AUTONOMOUS:-0}" != "1" ]; then
  # Non-trivial implementation ask, reasonably specified: compile the spec
  # inline (no confirm gate) so intent is pinned before code — the compiled
  # spec opens the reply and doubles as the plan's requirements section.
  cat <<EOF
{"systemMessage": "SPEC COMPILER: open your reply by compiling this request into GOAL / ACCEPTANCE (checkable) / OUT OF SCOPE / SUSPECTED FILES (max 8 lines total), then proceed directly to the work. If any ACCEPTANCE line cannot be stated checkably, that line is a question for the user — surface it instead of guessing."}
EOF
fi

exit 0
