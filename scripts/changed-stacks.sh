#!/usr/bin/env bash
# Prints a JSON array of the stacks a change touches, for use as a GitHub Actions matrix.
#   scripts/changed-stacks.sh origin/main
# Rules: a change under stacks/<name> selects that stack. A change under modules/, scripts/ or
# bootstrap-independent shared files selects every stack, because they all use the module.
set -euo pipefail
BASE="${1:-origin/main}"
ALL=$(ls stacks | sort)
CHANGED=$(git diff --name-only "$BASE"...HEAD)

if echo "$CHANGED" | grep -qE '^(modules/|scripts/tf.sh)'; then
  SELECT="$ALL"
else
  SELECT=$(echo "$CHANGED" | grep -E '^stacks/' | cut -d/ -f2 | sort -u || true)
fi

echo "$SELECT" | grep -v '^$' | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'
