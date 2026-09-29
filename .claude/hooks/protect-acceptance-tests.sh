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
# El engineer corre en un worktree aislado (isolation: worktree), en <repo>/.claude/worktrees/<n>/.
# Ahí toda ruta contiene /.claude/: se mide desde la raíz del worktree. Una ruta con .. no se
# reinterpreta (queda con /.claude/ y se bloquea abajo).
case "$path" in
  */.claude/worktrees/*/..*|*/.claude/worktrees/*/*/..*) ;;
  */.claude/worktrees/?*/?*) path=${path#*/.claude/worktrees/}; path=${path#*/} ;;
esac
case "$path" in
  *tests/acceptance/*|*CLAUDE.md|*/.claude/*|.claude/*|*LESSONS.md|*docs/adr/*|*.github/workflows/*)
    echo "Bloqueado: el engineer no puede modificar $path. Repórtalo en NOTES." >&2
    exit 2 ;;
esac
exit 0
