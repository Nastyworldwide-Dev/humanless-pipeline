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

# Detect vague/ambiguous language patterns
VAGUE_COUNT=$(echo "$PROMPT" | grep -ciE '(make it better|improve|optimize|clean up|fix it|make it work|something like|sort of|kind of|maybe|probably|etc\.)' || echo 0)

if [ "$VAGUE_COUNT" -gt 1 ]; then
  cat <<EOF
{"systemMessage": "This request contains ambiguous language. Before implementing, consider running /grill-me to clarify requirements, or ask the user to specify: (1) what 'better' means concretely, (2) acceptance criteria, (3) which files/modules are in scope."}
EOF
fi

exit 0
