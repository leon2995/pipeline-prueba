#!/usr/bin/env bash
# Hook del auditor: solo comandos de lectura o la suite de tests.
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
input=$(cat)
cmd=$(printf '%s' "$input" | json_get command)
[ -z "$cmd" ] && exit 0

allow='^(git (diff|log|show|status|branch)|npm test|npm run (test|lint|typecheck)|npx (vitest|jest|eslint|tsc)|uv run (pytest|ruff|mypy)|pytest|ruff|cat |head |tail |ls|wc |grep |rg |find |tree|python scripts/jev\.py)'
writes='(>|>>|\|[[:space:]]*tee|(^|[[:space:];&|])rm |(^|[[:space:];&|])mv |(^|[[:space:];&|])cp |chmod|chown|git (add|commit|push|checkout|switch|reset|rebase|merge|stash)|npm (install|i |ci)|pip install|uv (add|remove)|\.env)'

if printf '%s' "$cmd" | grep -Eq "$allow" && ! printf '%s' "$cmd" | grep -Eq "$writes"; then
  exit 0
fi
echo "Bloqueado: el auditor solo ejecuta comandos de lectura (git diff/log/show, tests, cat, grep). Intentaste: $cmd" >&2
exit 2
