#!/usr/bin/env bash
# Prueba los hooks de .claude/hooks: les pasa por stdin el JSON que manda Claude Code y
# verifica el código de salida (2 = bloquea, 0 = permite). Termina con 1 si algún caso falla.
# Uso: bash scripts/test-hooks.sh
set -uo pipefail
hooks="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks"
ok=0
fallos=0
extra_path=""   # se antepone al PATH del hook; sirve para simular herramientas rotas
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Escapa un texto para meterlo en un string JSON: \, " y saltos de línea.
esc() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

# caso <hook> <bloquea|permite> <json> <descripción>
caso() {
  local hook=$1 quiere=$2 json=$3 desc=${4//$'\n'/\\n} esperado=0 salio
  [ "$quiere" = bloquea ] && esperado=2
  printf '%s' "$json" | PATH="$extra_path$PATH" bash "$hooks/$hook" >/dev/null 2>&1
  salio=$?
  if [ "$salio" -eq "$esperado" ]; then
    ok=$((ok + 1))
    printf 'ok     %-8s %s\n' "$quiere" "$desc"
  else
    fallos=$((fallos + 1))
    printf 'FALLO  %-8s %s (esperaba %s, salió %s)\n' "$quiere" "$desc" "$esperado" "$salio"
  fi
}
# Atajos por tipo de evento: comando Bash, ruta de Edit/Write y Stop.
bash_cmd() { caso "$1" "$2" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$(esc "$3")\"}}" "$3"; }
archivo() { caso "$1" "$2" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$(esc "$3")\",\"content\":\"x\"}}" "$3"; }
stop() { caso run-tests.sh "$1" "{\"hook_event_name\":\"Stop\",\"cwd\":\"$(esc "$2")\",\"stop_hook_active\":$3}" "$4"; }

g() { bash_cmd guard-commands.sh "$@"; }

echo "== guard-commands.sh: push forzado (bloquea)"
g bloquea 'git push --force origin feat/x'
g bloquea 'git push origin feat/x --force-with-lease'
g bloquea 'git push -f origin feat/x'
g bloquea 'git push -uf origin feat/x'
g bloquea 'git push origin +feat/x'
g bloquea 'git push origin feat/x --force'
g bloquea 'git push origin feat/x -f'
g bloquea 'git push -fu origin feat/x'
g bloquea 'git push --force-with-lease=feat/x origin feat/x'
g bloquea 'git push --force-if-includes origin feat/x'
g bloquea 'git push origin "+feat/x"'
g bloquea 'git push origin +HEAD:feat/x'
g bloquea 'git push --mirror origin'
g bloquea 'git push --mirr origin'
g bloquea 'GIT_TRACE=1 git -C . push -f origin feat/x'
g bloquea 'git -c remote.origin.push=+refs/heads/*:refs/heads/* push origin'
g bloquea 'git status && git push -f origin feat/x'
g bloquea 'bash -c "git push -f origin feat/x"'
g bloquea 'git push origin feat/x \
  --force'

echo "== guard-commands.sh: borrado de ramas (bloquea)"
g bloquea 'git branch -D rama-que-no-existe'
g bloquea 'git branch -d rama-que-no-existe'
g bloquea 'git branch --delete rama-que-no-existe'
g bloquea 'git branch -rd origin/rama'

echo "== guard-commands.sh: main y merge (bloquea)"
g bloquea 'git push origin main'
g bloquea 'gh pr merge 1 --squash --admin'

echo "== guard-commands.sh: permitidos"
g permite 'git status'
g permite 'npm test'
g permite 'git push -u origin feat/x'
g permite 'git push --follow-tags origin feat/x'
g permite 'git push origin feat/x'
g permite 'git push -u origin fix/hook-force-push'
g permite 'git push -u origin feat/x && ls -f'
g permite 'git commit -m "docs: explica por qué push --force está prohibido"'
g permite 'git stash push -m wip'
g permite 'git branch --merged'
g permite 'git branch -m viejo nuevo'
g permite 'git branch fix-db-deploy'

echo "== guard-commands.sh: falso positivo aceptado (no respeta comillas, para ver dentro de bash -c)"
g bloquea 'git commit -m "revertir el git push --force de ayer"'

echo "== guard-commands.sh: awk roto (fail-closed solo si el comando menciona push)"
mkdir -p "$tmp/awk-roto"
printf '#!/bin/sh\nexit 2\n' > "$tmp/awk-roto/awk"
chmod +x "$tmp/awk-roto/awk"
extra_path="$tmp/awk-roto:"
g bloquea 'git push -u origin feat/x'
g permite 'git status'
extra_path=""

echo "== readonly-guard.sh (auditor)"
r() { bash_cmd readonly-guard.sh "$@"; }
r permite 'git diff staging...HEAD'
r permite 'git log --oneline -5'
r permite 'npm test'
r bloquea 'git commit -m x'
r bloquea 'git push origin feat/x'
r bloquea 'git diff staging...HEAD > cambios.patch'
r bloquea 'rm archivo.txt'

echo "== protect-acceptance-tests.sh (engineer)"
p() { archivo protect-acceptance-tests.sh "$@"; }
p bloquea 'tests/acceptance/test_c1.py'
p bloquea '.claude/settings.json'
p bloquea '/repo/.claude/hooks/guard-commands.sh'
p bloquea 'CLAUDE.md'
p bloquea 'LESSONS.md'
p bloquea 'docs/adr/0001-stack.md'
p bloquea '.github/workflows/ci.yml'
p permite 'src/app.py'
p permite 'tests/unit/test_app.py'

echo "== only-acceptance-tests.sh (test-writer)"
o() { archivo only-acceptance-tests.sh "$@"; }
o permite 'tests/acceptance/test_c1.py'
o bloquea 'src/app.py'
o bloquea 'tests/unit/test_app.py'

echo "== run-tests.sh (Stop del engineer)"
mkdir -p "$tmp/rojo/.pipeline" "$tmp/verde"
printf '{"scripts":{"test":"exit 1"}}\n' > "$tmp/rojo/package.json"
printf '{"scripts":{"test":"exit 0"}}\n' > "$tmp/verde/package.json"
stop permite "$tmp" false 'proyecto sin package.json ni pyproject.toml'
stop permite "$tmp/rojo" true 'tests en rojo con stop_hook_active (evita bucle)'
if command -v npm >/dev/null 2>&1; then
  stop bloquea "$tmp/rojo" false 'tests en rojo'
  stop permite "$tmp/verde" false 'tests en verde'
  touch "$tmp/rojo/.pipeline/BLOCKED"
  stop permite "$tmp/rojo" false 'tests en rojo con .pipeline/BLOCKED'
else
  echo "omitido: npm no está instalado (casos de tests en rojo y en verde)"
fi

echo
echo "$ok ok, $fallos fallos"
[ "$fallos" -eq 0 ] || exit 1
