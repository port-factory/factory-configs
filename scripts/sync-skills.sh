#!/bin/sh
# Copies the skills from .agents/skills (the source of truth) to each agent's skills folder.
# Run after editing a skill. `--check` fails if any copy is out of date (used in CI).
set -e
cd "$(dirname "$0")/.."
for target in .claude/skills .cursor/skills; do
  if [ "$1" = "--check" ]; then
    diff -r .agents/skills "$target" > /dev/null || { echo "$target is out of date: run scripts/sync-skills.sh"; exit 1; }
  else
    rm -rf "$target" && mkdir -p "$(dirname "$target")" && cp -R .agents/skills "$target"
  fi
done
echo "skills in sync"
