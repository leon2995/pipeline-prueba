#!/usr/bin/env bash
# Stop hook del engineer: no puede terminar con tests en rojo.
# Excepciones: ya venimos de un stop bloqueado (evita bucle) o el engineer declaró BLOCKED.
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
input=$(cat)
cwd=$(printf '%s' "$input" | json_get cwd)
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd"
active=$(printf '%s' "$input" | json_get stop_hook_active)
if [ "$active" = "true" ]; then exit 0; fi
if [ -f .pipeline/BLOCKED ]; then exit 0; fi

if [ -f package.json ]; then
  out=$(npm test --silent 2>&1); rc=$?
elif [ -f pyproject.toml ]; then
  out=$(uv run pytest -q 2>&1); rc=$?
else
  exit 0
fi

if [ $rc -ne 0 ]; then
  echo "Tests en rojo. No puedes terminar. Corrige y vuelve a correr la suite. Últimas líneas:" >&2
  echo "$out" | tail -n 40 >&2
  exit 2
fi
exit 0
