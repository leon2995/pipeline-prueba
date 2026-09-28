#!/usr/bin/env bash
# Hook del engineer: no puede tocar tests de aceptación ni archivos de gobierno del repo.
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
input=$(cat)
path=$(printf '%s' "$input" | json_get file_path)
[ -z "$path" ] && path=$(printf '%s' "$input" | json_get path)
[ -z "$path" ] && exit 0
# Rutas Windows: jq nativo puede dejar un \r final y Claude Code entrega C:\...\x con \.
path=${path%$'\r'}
path=${path//\\//}
case "$path" in
  *tests/acceptance/*|*CLAUDE.md|*/.claude/*|.claude/*|*LESSONS.md|*docs/adr/*|*.github/workflows/*)
    echo "Bloqueado: el engineer no puede modificar $path. Repórtalo en NOTES." >&2
    exit 2 ;;
esac
exit 0
