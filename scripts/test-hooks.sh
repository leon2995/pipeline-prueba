#!/usr/bin/env bash
# Prueba los hooks de .claude/hooks: les pasa por stdin el JSON que manda Claude Code y
# verifica el código de salida (2 = bloquea, 0 = permite). Termina con 1 si algún caso falla.
# Uso: bash scripts/test-hooks.sh
set -uo pipefail
hooks="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks"
ok=0
fallos=0
extra_path=""   # se antepone al PATH del hook; sirve para simular herramientas rotas o un gh falso
hooks_alt=""    # si no está vacío, se corre el hook de este directorio (copia) en lugar del real
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

# caso <hook> <bloquea|permite> <json> <descripción> [motivo]
# Con motivo, además del código de salida exige que stderr contenga ese texto: un hook
# fail-closed puede bloquear por una razón distinta de la que se quiere probar.
caso() {
  local hook=$1 quiere=$2 json=$3 desc=${4//$'\n'/\\n} motivo=${5:-} esperado=0 salio err
  [ "$quiere" = bloquea ] && esperado=2
  err=$(printf '%s' "$json" | PATH="$extra_path$PATH" bash "${hooks_alt:-$hooks}/$hook" 2>&1 >/dev/null)
  salio=$?
  if [ "$salio" -eq "$esperado" ] && { [ -z "$motivo" ] || [[ "$err" == *"$motivo"* ]]; }; then
    ok=$((ok + 1))
    printf 'ok     %-8s %s\n' "$quiere" "$desc"
  else
    fallos=$((fallos + 1))
    printf 'FALLO  %-8s %s (esperaba %s, salió %s)%s\n' "$quiere" "$desc" "$esperado" "$salio" \
      "${motivo:+; motivo esperado: \"$motivo\"; stderr: \"$err\"}"
  fi
}
# Atajos por tipo de evento: comando Bash, ruta de Edit/Write y Stop.
bash_cmd() { caso "$1" "$2" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$(esc "$3")\"}}" "$3" "${4:-}"; }
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

echo "== guard-commands.sh: push forzado escondido con comillas, escapes, redirecciones o abreviaturas (bloquea)"
g bloquea 'git push origin --for"ce" feature-x'
g bloquea 'git push -"f" origin feat/x'
g bloquea "git push --forc'e' origin feat/x"
g bloquea 'git p\ush -f origin feat/x'
g bloquea '"git" push -f origin feat/x'
g bloquea 'git >/dev/null push -f origin feat/x'
g bloquea 'git > /dev/null push -f origin feat/x'
g bloquea 'git 2>&1 push -f origin feat/x'
g bloquea 'git push -f origin feat/x &>/dev/null'
g bloquea 'git push --m origin'
g bloquea 'git push --force-w origin feat/x'
g bloquea 'git push --forc origin feat/x'
g bloquea '"C:\Program Files\Git\bin\git.exe" push -f origin feat/x'
g bloquea "git push origin \$'-f' feat/x"
g bloquea "GIT_CONFIG_PARAMETERS=\"'remote.origin.push=+refs/heads/*:refs/heads/*'\" git push origin"
g bloquea 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.mirror GIT_CONFIG_VALUE_0=true git push origin'
# \r final: jq nativo de Windows entrega el comando con CRLF.
caso guard-commands.sh bloquea '{"tool_name":"Bash","tool_input":{"command":"git push -f origin feat/x\r"}}' 'git push -f origin feat/x + \r final'

echo "== guard-commands.sh: borrado de ramas (bloquea)"
g bloquea 'git branch -D rama-que-no-existe'
g bloquea 'git branch -d rama-que-no-existe'
g bloquea 'git branch --delete rama-que-no-existe'
g bloquea 'git branch -rd origin/rama'
g bloquea 'git branch -rD origin/rama'
g bloquea "git branch '-d' rama"
g bloquea 'git branch "-D" rama'
g bloquea 'git branch -\D rama'
g bloquea 'git branch --del rama'
g bloquea 'git -C . branch -d rama'
g bloquea 'git >/dev/null branch -d rama'
g bloquea 'git push origin --delete feat/x'
g bloquea 'git push origin -d feat/x'
g bloquea 'git push origin :feat/x'
g bloquea 'git update-ref -d refs/heads/feat/x'

echo "== guard-commands.sh: main y merge (bloquea)"
g bloquea 'git push origin main'
g bloquea "git push origin 'main'"
g bloquea 'git push origin HEAD:main'
g bloquea 'git push origin HEAD:refs/heads/main'
g bloquea 'git push -u origin main 2>&1'
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
g permite 'git branch --sort=-committerdate'
g permite 'git push --fol origin feat/x'
g permite 'git push origin feat/x 2>&1 | tail -5'
g permite 'git push origin feat/main-fix'
g permite 'git push origin main:feat/x'
g permite 'git push origin feat/x && git checkout main'
g permite 'git checkout main'
g permite 'git push --dry-run origin feat/x'
g permite 'GIT_CONFIG_NOSYSTEM=1 git push -u origin feat/x'

echo "== guard-commands.sh: falso positivo aceptado (no respeta comillas, para ver dentro de bash -c)"
g bloquea 'git commit -m "revertir el git push --force de ayer"'

echo "== guard-commands.sh: awk roto (fail-closed solo si el comando menciona push o branch)"
for codigo in 0 1 2; do
  mkdir -p "$tmp/awk-$codigo"
  printf '#!/bin/sh\nexit %s\n' "$codigo" > "$tmp/awk-$codigo/awk"
  chmod +x "$tmp/awk-$codigo/awk"
  extra_path="$tmp/awk-$codigo:"
  echo "-- awk sale con $codigo sin imprimir nada"
  g bloquea 'git push -u origin feat/x'
  g bloquea 'git branch -d rama'
  g permite 'git status'
done
extra_path=""

# gh falso: responde solo las consultas que hace guard-commands.sh, según el número de PR.
# También responde la consulta del hook anterior (--json baseRefName -q .baseRefName) para que
# la suite corrida contra hooks viejos (mutación) falle por la regla y no por el gh falso.
mkdir -p "$tmp/gh-falso"
cat > "$tmp/gh-falso/gh" <<'GH'
#!/usr/bin/env bash
args="$*"
n=$(printf '%s\n' "$@" | grep -Eo '^[0-9]+$|/pulls/[0-9]+/' | grep -Eo '[0-9]+' | head -n1)
[ -z "$n" ] && n=101   # sin número: PR de la rama actual
base=staging total="" renombres=() falla_api=0
case "$n" in
  101) rutas=(src/app.py) ;;
  102) rutas=(CLAUDE.md) ;;
  103) rutas=(sub/CLAUDE.md) ;;
  104) rutas=(LESSONS.md) ;;
  105) rutas=(.claude/hooks/guard-commands.sh) ;;
  106) rutas=(sub/.claude/settings.json) ;;
  107) rutas=(.github/workflows/ci.yml) ;;
  108) rutas=(scripts/jev.py) ;;
  109) rutas=(scripts/test-hooks.sh) ;;
  110) rutas=(scripts/run-task.sh) ;;
  111) rutas=(scripts/resume-task.sh) ;;
  112) rutas=(scripts/watch-deploy.sh) ;;
  113) rutas=(scripts/router/jev.py) renombres=(scripts/jev.py) ;;
  115) base=main rutas=(src/app.py) ;;
  116) exit 1 ;;
  117) rutas=(src/app.py) falla_api=1 ;;
  118) rutas=(src/app.py) total=150 ;;
  119) rutas=() ;;
  131) rutas=(docs/claude-notas.md) ;;
  132) rutas=(docs/MYCLAUDE.md) ;;
  133) rutas=(scripts/jev.py.bak) ;;
  134) rutas=(src/scripts/jev.py) ;;
  135) rutas=(.claude-old/x) ;;
  136) rutas=(docs/.github/x) ;;
  *) exit 1 ;;
esac
[ -z "$total" ] && total=${#rutas[@]}
case "$args" in
  "pr view"*"--json number,baseRefName,changedFiles,files --jq "*)
    printf '%s\n' "$n" "$base" "$total" "${#rutas[@]}" ${rutas[@]+"${rutas[@]}"} ;;
  "pr view"*"--json baseRefName -q .baseRefName")
    printf '%s\n' "$base" ;;
  "api repos/{owner}/{repo}/pulls/$n/files --paginate --jq "*)
    [ "$falla_api" = 1 ] && exit 1
    [ ${#renombres[@]} -gt 0 ] && printf '%s\n' "${renombres[@]}" ;;
  *) exit 1 ;;
esac
exit 0
GH
chmod +x "$tmp/gh-falso/gh"

echo "== guard-commands.sh: gh pr merge y rutas de gobierno (.claude/rutas-gobierno.txt), con gh falso"
extra_path="$tmp/gh-falso:"
g permite 'gh pr merge 101 --squash'
g bloquea 'gh pr merge --squash' 'indica el número del PR'
g bloquea 'git switch fix/gobierno && gh pr merge --squash' 'indica el número del PR'
g bloquea 'gh pr merge fix/gobierno --squash' 'indica el número del PR'
g bloquea 'gh pr merge https://github.com/o/r/pull/102 --squash' 'indica el número del PR'
g bloquea 'gh pr merge 102 --squash' 'ruta de gobierno CLAUDE.md'
g bloquea 'gh pr merge 103 --squash' 'ruta de gobierno sub/CLAUDE.md'
g bloquea 'gh pr merge 104 --squash' 'ruta de gobierno LESSONS.md'
g bloquea 'gh pr merge 105 --squash' 'ruta de gobierno .claude/hooks/guard-commands.sh'
g bloquea 'gh pr merge 106 --squash' 'ruta de gobierno sub/.claude/settings.json'
g bloquea 'gh pr merge 107 --squash' 'ruta de gobierno .github/workflows/ci.yml'
g bloquea 'gh pr merge 108 --squash' 'ruta de gobierno scripts/jev.py'
g bloquea 'gh pr merge 109 --squash' 'ruta de gobierno scripts/test-hooks.sh'
g bloquea 'gh pr merge 110 --squash' 'ruta de gobierno scripts/run-task.sh'
g bloquea 'gh pr merge 111 --squash' 'ruta de gobierno scripts/resume-task.sh'
g bloquea 'gh pr merge 112 --squash' 'ruta de gobierno scripts/watch-deploy.sh'
g bloquea 'gh pr merge 113 --squash' 'ruta de gobierno scripts/jev.py'
g permite 'gh pr merge 131 --squash'
g permite 'gh pr merge 132 --squash'
g permite 'gh pr merge 133 --squash'
g permite 'gh pr merge 134 --squash'
g permite 'gh pr merge 135 --squash'
g permite 'gh pr merge 136 --squash'
g bloquea 'gh pr merge 115 --squash' 'base staging'
g bloquea 'gh pr merge 116 --squash' 'no pude consultar el PR'
g bloquea 'gh pr merge 117 --squash' 'no pude consultar los renombres'
g bloquea 'gh pr merge 118 --squash' 'lista incompleta'
g bloquea 'gh pr merge 119 --squash' 'sin archivos'
g bloquea 'gh pr merge 101 --squash && gh pr merge 102 --squash' 'un merge por comando'
g bloquea 'gh pr merge 101 102' 'un único PR'
g permite 'gh pr merge --subject 7 101'
g bloquea 'gh pr merge -t 7 102' 'ruta de gobierno CLAUDE.md'
g permite 'gh pr merge 101 --body "texto con espacios"'
g bloquea 'gh pr merge 101 --body "sin cerrar' 'comillas'
g bloquea 'gh pr merge -R otro/repo 101' 'otro repositorio'
g bloquea 'gh pr merge -Rotro/repo 101' 'otro repositorio'
echo "-- redirecciones y separadores dentro de comillas"
g permite 'gh pr merge 101 --squash 2>&1'
g permite 'gh pr merge 101 --squash 2>/dev/null'
g permite 'gh pr merge 101 --squash > merge.log'
g permite 'gh pr merge 101 --squash >merge.log'
g permite 'gh pr merge 101 --squash &>/dev/null'
g permite 'gh pr merge 101 --squash 2>&1 | tail -5'
g bloquea 'gh pr merge 102 --squash 2>&1' 'ruta de gobierno CLAUDE.md'
g bloquea 'gh pr merge 102 --squash > merge.log' 'ruta de gobierno CLAUDE.md'
g permite 'gh pr merge 101 --body "R&D listo" --squash'
g permite 'gh pr merge 101 --body "revisión; lista" --squash'
g permite "gh pr merge 101 --subject 'a | b' --squash"
g bloquea 'gh pr merge 102 --body "R&D; listo" --squash' 'ruta de gobierno CLAUDE.md'
g bloquea 'gh pr merge 101 --body "sigue a gh pr merge 100"' 'un merge por comando'
echo "-- formas de escribir el merge"
g permite 'echo hola && gh pr merge 101 --squash'
g permite 'gh pr merge 101 --squash # listo'
g bloquea '(gh pr merge 102 --squash)' 'ruta de gobierno CLAUDE.md'
g bloquea 'gh pr -R otro/repo merge 101' 'sin nada entre gh, pr y merge'
g bloquea 'gh  pr merge 102 --squash' 'sin nada entre gh, pr y merge'
g bloquea 'gh pr merge; echo listo' 'indica el número del PR'
g bloquea 'GH_REPO=otro/repo gh pr merge 101 --squash' 'GH_REPO'
g permite 'gh pr create --title "fix merge conflicts" --body x'
g permite 'gh pr comment 101 --body "please merge"'
g permite 'gh pr view 101 --json mergeable'

echo "== guard-commands.sh: flags de gh pr merge, con gh falso"
g bloquea 'gh pr merge 101 -d' 'borrar ramas'
g bloquea 'gh pr merge 101 --delete-branch' 'borrar ramas'
g bloquea 'gh pr merge 101 --squash -d' 'borrar ramas'
g bloquea 'gh pr merge 101 -sd' 'borrar ramas'
g bloquea 'gh pr merge 101 --auto' 'sin --auto'
g bloquea 'gh pr merge 101 --squash --auto' 'sin --auto'
g bloquea 'gh pr merge 101 --admin=true' '--admin'
g bloquea 'gh pr merge 101 --admin=false' '--admin'
g bloquea 'gh pr merge 101 --auto=true' 'sin --auto'
g bloquea 'gh pr merge 101 --delete-branch=true' 'borrar ramas'
g bloquea 'gh pr merge 101 -d=true' 'borrar ramas'
g bloquea 'gh pr merge 101 -sd=true' 'borrar ramas'
g bloquea 'gh pr merge 101 -ds' 'borrar ramas'
g permite 'gh pr merge 101 -tdocs'
g permite 'gh pr merge 101 -bdone'
g permite 'gh pr merge 101 -t=7'
g permite 'gh pr merge 101 -st asunto'
g bloquea 'gh pr merge -st 7 102' 'ruta de gobierno CLAUDE.md'
g permite 'gh pr merge 101 --merge'
g permite 'gh pr merge 101 --rebase'
g permite 'gh pr merge 101 --disable-auto'
g permite 'gh pr merge 101 -s'
g permite 'gh pr merge 101 -m'
g permite 'gh pr merge 101 -r'
g permite 'gh pr merge 101 --subject x'
g permite 'gh pr merge 101 --body x'
g permite 'gh pr merge 101 --match-head-commit abc123'

echo "== guard-commands.sh: archivo de reglas, con una copia del hook y gh falso"
# variante <nombre>: copia guard-commands.sh y _lib.sh a $tmp/reglas/<nombre>/.claude/hooks y la usa.
variante() {
  mkdir -p "$tmp/reglas/$1/.claude/hooks"
  cp "$hooks/guard-commands.sh" "$hooks/_lib.sh" "$tmp/reglas/$1/.claude/hooks/"
  hooks_alt="$tmp/reglas/$1/.claude/hooks"
  echo "-- $1"
}
variante control
cp "$hooks/../rutas-gobierno.txt" "$tmp/reglas/control/.claude/" 2>/dev/null
g permite 'gh pr merge 101 --squash'
g bloquea 'gh pr merge 102 --squash' 'ruta de gobierno CLAUDE.md'
variante ausente
g bloquea 'gh pr merge 101 --squash' 'no pude leer'
variante vacio
printf '# solo comentarios\n\n   \n' > "$tmp/reglas/vacio/.claude/rutas-gobierno.txt"
g bloquea 'gh pr merge 101 --squash' 'no tiene reglas'
variante ilegible
mkdir "$tmp/reglas/ilegible/.claude/rutas-gobierno.txt"
g bloquea 'gh pr merge 101 --squash' 'no pude leer'
variante crlf
awk '{ printf "%s\r\n", $0 }' "$hooks/../rutas-gobierno.txt" > "$tmp/reglas/crlf/.claude/rutas-gobierno.txt" 2>/dev/null
g permite 'gh pr merge 101 --squash'
g bloquea 'gh pr merge 102 --squash' 'ruta de gobierno CLAUDE.md'
variante no-soportada
printf '**/CLAUDE.md\n*.sh\n' > "$tmp/reglas/no-soportada/.claude/rutas-gobierno.txt"
g bloquea 'gh pr merge 101 --squash' 'regla no soportada'
hooks_alt=""
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
echo "-- rutas Windows absolutas (Claude Code en Windows entrega C:\\...\\x)"
p bloquea 'C:\Users\dev\repo\tests\acceptance\test_c1.py'
p bloquea 'C:\Users\dev\repo\.claude\settings.json'
p bloquea 'C:\Users\dev\repo\.claude\hooks\guard-commands.sh'
p bloquea 'C:\Users\dev\repo\CLAUDE.md'
p bloquea 'C:\Users\dev\repo\LESSONS.md'
p bloquea 'C:\Users\dev\repo\docs\adr\0001-stack.md'
p bloquea 'C:\Users\dev\repo\.github\workflows\ci.yml'
p permite 'C:\Users\dev\repo\src\app.py'
p permite 'C:\Users\dev\repo\tests\unit\test_app.py'
# \r final: jq nativo de Windows entrega la ruta con CRLF.
caso protect-acceptance-tests.sh bloquea '{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\dev\\repo\\CLAUDE.md\r"}}' 'C:\Users\dev\repo\CLAUDE.md + \r final'

echo "== only-acceptance-tests.sh (test-writer)"
o() { archivo only-acceptance-tests.sh "$@"; }
o permite 'tests/acceptance/test_c1.py'
o bloquea 'src/app.py'
o bloquea 'tests/unit/test_app.py'
echo "-- rutas Windows absolutas"
o permite 'C:\Users\dev\repo\tests\acceptance\test_c1.py'
o bloquea 'C:\Users\dev\repo\.claude\settings.json'
o bloquea 'C:\Users\dev\repo\.claude\hooks\guard-commands.sh'
o bloquea 'C:\Users\dev\repo\CLAUDE.md'
o bloquea 'C:\Users\dev\repo\LESSONS.md'
o bloquea 'C:\Users\dev\repo\docs\adr\0001-stack.md'
o bloquea 'C:\Users\dev\repo\.github\workflows\ci.yml'
o bloquea 'C:\Users\dev\repo\src\app.py'
o bloquea 'C:\Users\dev\repo\tests\unit\test_app.py'
caso only-acceptance-tests.sh permite '{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\dev\\repo\\tests\\acceptance\\test_c1.py\r"}}' 'C:\Users\dev\repo\tests\acceptance\test_c1.py + \r final'

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
