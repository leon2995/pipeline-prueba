#!/usr/bin/env bash
# Hook del test-writer: solo escribe dentro de tests/acceptance/.
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
input=$(cat)
path=$(printf '%s' "$input" | json_get file_path)
[ -z "$path" ] && path=$(printf '%s' "$input" | json_get path)
[ -z "$path" ] && exit 0
case "$path" in
  *tests/acceptance/*) exit 0 ;;
  *) echo "Bloqueado: test-writer solo escribe en tests/acceptance/ (intentaste $path)." >&2; exit 2 ;;
esac
