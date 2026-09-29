#!/usr/bin/env bash
# Prueba los hooks de .claude/hooks: les pasa por stdin el JSON que manda Claude Code y
# verifica el código de salida (2 = bloquea, 0 = permite). Termina con 1 si algún caso falla.
# Uso: bash scripts/test-hooks.sh
set -uo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
ok=0
fallos=0
extra_path=""   # se antepone al PATH del hook; sirve para simular herramientas rotas o un gh falso
hooks_alt=""    # si no está vacío, se corre el hook de este directorio (copia) en lugar del base
extra_env=()    # variables de entorno para el hook (por ejemplo la identidad de talos-bot-leon)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# La suite corre sobre una copia de los hooks y de rutas-gobierno.txt, sin identidad-agente.txt:
# el resultado no depende de que la identidad del agente esté activada en el repo (C4).
mkdir -p "$tmp/base/.claude/hooks"
cp "$repo"/.claude/hooks/*.sh "$tmp/base/.claude/hooks/"
cp "$repo/.claude/rutas-gobierno.txt" "$tmp/base/.claude/" 2>/dev/null
hooks="$tmp/base/.claude/hooks"

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
  # El hook corre sin las variables de identidad de la sesión que lanza la suite (salvo las que
  # el caso pida en extra_env), para que el resultado no dependa de quién la corre.
  err=$(printf '%s' "$json" | env -u GH_CONFIG_DIR -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 \
    -u GIT_CONFIG_VALUE_0 -u GIT_CONFIG_KEY_1 -u GIT_CONFIG_VALUE_1 -u GIT_AUTHOR_NAME \
    -u GIT_COMMITTER_NAME -u GH_TOKEN -u GITHUB_TOKEN -u FAKE_GH_LOGIN ${extra_env[@]+"${extra_env[@]}"} \
    PATH="$extra_path$PATH" bash "${hooks_alt:-$hooks}/$hook" 2>&1 >/dev/null)
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

# chequeo <pasa|falla> <descripción> <comando...>: corre un comando de verificación (no un hook).
chequeo() {
  local quiere=$1 desc=$2 salio
  shift 2
  "$@" >/dev/null 2>&1
  salio=$?
  if { [ "$quiere" = pasa ] && [ "$salio" -eq 0 ]; } || { [ "$quiere" = falla ] && [ "$salio" -ne 0 ]; }; then
    ok=$((ok + 1))
    printf 'ok     %-8s %s\n' "$quiere" "$desc"
  else
    fallos=$((fallos + 1))
    printf 'FALLO  %-8s %s (salió %s)\n' "$quiere" "$desc" "$salio"
  fi
}

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
g bloquea 'GIT_CONFIG_NOSYSTEM=1 git push -u origin feat/x' 'identidad'

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
  "api user --jq .login")
    [ -n "${FAKE_GH_LOGIN:-}" ] || exit 1
    printf '%s\n' "$FAKE_GH_LOGIN" ;;
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
variante barra-interna-dir
printf '**/CLAUDE.md\n**/docs/adr/\n' > "$tmp/reglas/barra-interna-dir/.claude/rutas-gobierno.txt"
g bloquea 'gh pr merge 101 --squash' 'regla no soportada'
variante barra-interna-archivo
printf '**/a/CLAUDE.md\n' > "$tmp/reglas/barra-interna-archivo/.claude/rutas-gobierno.txt"
g bloquea 'gh pr merge 101 --squash' 'regla no soportada'
hooks_alt=""
extra_path=""

echo "== guard-commands.sh: credenciales (bloquea)"
g bloquea 'grep -rn GH_TOKEN .' 'credenciales'
g bloquea 'echo "$GH_TOKEN"' 'credenciales'
g bloquea 'echo ${GITHUB_TOKEN}' 'credenciales'
g bloquea 'echo ghp_' 'credenciales'
g bloquea 'echo github_pat_' 'credenciales'
g bloquea 'cat .claude/settings.local.json' 'credenciales'
g bloquea 'grep -rn helper .claude/settings.local.json' 'credenciales'
g bloquea 'cat ~/.talos-gh/hosts.yml' 'credenciales'
g bloquea 'ls ~/.talos-gh' 'credenciales'
g bloquea 'gh auth token' 'credenciales'
g bloquea 'gh auth status -t' 'credenciales'
g bloquea 'gh auth status --show-token' 'credenciales'
g bloquea 'gh auth git-credential get' 'credenciales'
g bloquea 'git credential fill < /dev/null' 'credenciales'
g bloquea 'git credential approve' 'credenciales'
g bloquea 'env' 'credenciales'
g bloquea 'ls && env' 'credenciales'
g bloquea 'env | sort' 'credenciales'
g bloquea 'printenv' 'credenciales'
g bloquea 'set' 'credenciales'
g bloquea 'export' 'credenciales'
g bloquea 'export -p' 'credenciales'
g bloquea 'declare -p' 'credenciales'
g bloquea 'declare -x' 'credenciales'
g bloquea 'typeset' 'credenciales'
g bloquea 'printenv -0' 'credenciales'
g bloquea 'env -u FOO' 'credenciales'
g bloquea 'env LANG=C' 'credenciales'
g bloquea 'gh --hostname github.com auth token' 'credenciales'
g bloquea 'gh auth --hostname github.com status -t' 'credenciales'
g bloquea 'gh config get -h github.com oauth_token' 'credenciales'

echo "== guard-commands.sh: cambio de identidad (bloquea)"
g bloquea 'gh auth login' 'identidad'
g bloquea 'gh auth logout' 'identidad'
g bloquea 'gh auth switch -u leon2995' 'identidad'
g bloquea 'gh auth refresh -s workflow' 'identidad'
g bloquea 'gh auth setup-git' 'identidad'
g bloquea 'GH_CONFIG_DIR= gh pr list' 'identidad'
g bloquea 'unset GH_CONFIG_DIR' 'identidad'
g bloquea 'export GIT_CONFIG_COUNT=0' 'identidad'
g bloquea 'GIT_CONFIG_PARAMETERS=x git push origin feat/x' 'identidad'
g bloquea 'git -c credential.helper= push origin feat/x' 'identidad'
g bloquea 'git config --global credential.helper manager' 'identidad'
g bloquea 'git config credential.https://github.com.helper x' 'identidad'
g bloquea 'env -i bash' 'identidad'
g bloquea 'env - git push -u origin feat/x' 'identidad'

echo "== guard-commands.sh: aprobación de PRs (bloquea)"
g bloquea 'gh pr review 5 --approve' 'aprobación'
g bloquea 'gh pr review 5 -a' 'aprobación'
g bloquea 'gh pr review 5 -a -b ok' 'aprobación'
g bloquea 'gh pr -R leon2995/pipeline-prueba review 5 --approve' 'aprobación'
g bloquea 'gh -R leon2995/pipeline-prueba pr review 5 -a' 'aprobación'

echo "== guard-commands.sh: credenciales e identidad (permitidos)"
g permite 'gh auth status'
g permite 'gh pr review 5 --comment -b "ok"'
g permite 'gh pr review 5 -r -b "faltan pruebas"'
g permite 'gh pr merge --help'
g permite 'gh pr merge 101 --help'
g permite 'git add .claude/settings.local.example.json'
g permite 'set -e'
g permite 'export FOO=1'
g permite 'declare -a lista'
g permite 'git config --get user.name'
g permite 'env LANG=C sort'
g permite 'env -u FOO python x.py'
g permite 'printenv PATH'
g permite 'printenv -0 PATH'
g permite 'env LC_ALL=C sed -i s/a/b/ f'
g permite 'env LANG=C sort -'

echo "== guard-commands.sh: identidad de talos-bot-leon (C4), con copia del hook y gh falso"
# variante_identidad <nombre> <contenido>: copia del hook con .claude/identidad-agente.txt.
variante_identidad() {
  variante "$1"
  cp "$hooks/../rutas-gobierno.txt" "$tmp/reglas/$1/.claude/" 2>/dev/null
  printf '%s\n' "$2" > "$tmp/reglas/$1/.claude/identidad-agente.txt"
}
# Identidad completa de talos-bot-leon, igual que la plantilla (sin token: el gh falso responde api user).
clave_helper='credential.https://github.com.helper'
talos_git=(GIT_CONFIG_COUNT=2 "GIT_CONFIG_KEY_0=$clave_helper" GIT_CONFIG_VALUE_0=
  "GIT_CONFIG_KEY_1=$clave_helper" 'GIT_CONFIG_VALUE_1=!gh auth git-credential')
talos_env=(GH_CONFIG_DIR=/tmp/talos-gh-prueba "${talos_git[@]}" GIT_AUTHOR_NAME=talos-bot-leon
  GIT_COMMITTER_NAME=talos-bot-leon FAKE_GH_LOGIN=talos-bot-leon)
extra_path="$tmp/gh-falso:"
variante_identidad identidad talos-bot-leon
echo "-- sin la identidad de talos-bot-leon"
extra_env=()
g bloquea 'git commit -m x' 'identidad de talos-bot-leon'
g bloquea 'git push -u origin feat/x' 'identidad de talos-bot-leon'
g bloquea 'gh pr create --title x --body y' 'identidad de talos-bot-leon'
g bloquea 'gh pr merge 101 --squash' 'identidad de talos-bot-leon'
g bloquea 'gh pr comment 101 --body x' 'identidad de talos-bot-leon'
g bloquea 'gh api repos/{owner}/{repo}/issues/5/comments -f body=x' 'identidad de talos-bot-leon'
g bloquea 'gh api graphql -f query=x' 'identidad de talos-bot-leon'
g bloquea 'gh api -X PATCH repos/{owner}/{repo}/pulls/5 --input datos.json' 'identidad de talos-bot-leon'
g bloquea 'gh api --method DELETE repos/{owner}/{repo}/git/refs/heads/x' 'identidad de talos-bot-leon'
g bloquea 'gh pr create --title x --body y; gh pr view --help' 'identidad de talos-bot-leon'
g bloquea 'gh pr new --fill' 'identidad de talos-bot-leon'
g bloquea 'gh -R leon2995/pipeline-prueba pr create --title x --body y' 'identidad de talos-bot-leon'
g bloquea 'gh pr -R leon2995/pipeline-prueba edit 5 --title x' 'identidad de talos-bot-leon'
g bloquea 'gh pr edit 5 --title x' 'identidad de talos-bot-leon'
g bloquea 'gh pr close 5' 'identidad de talos-bot-leon'
g bloquea 'gh pr reopen 5' 'identidad de talos-bot-leon'
g bloquea 'gh pr ready 5' 'identidad de talos-bot-leon'
g bloquea 'gh pr review 5 --comment -b x' 'identidad de talos-bot-leon'
g bloquea 'gh api repos/{owner}/{repo}/issues/1 -X GET -X DELETE' 'identidad de talos-bot-leon'
g bloquea 'gh api repos/{owner}/{repo}/issues/1 -X DELETE -X GET' 'identidad de talos-bot-leon'
g bloquea 'gh api -X "POST" repos/{owner}/{repo}/issues/5/comments' 'identidad de talos-bot-leon'
g bloquea 'gh api -X GET repos/{owner}/{repo}/pulls/5; gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/x' 'identidad de talos-bot-leon'
g bloquea 'gh --repo leon2995/pipeline-prueba api repos/{owner}/{repo}/issues -f title=x' 'identidad de talos-bot-leon'
g bloquea 'git -C . push -u origin feat/x' 'identidad de talos-bot-leon'
g permite 'gh api -XGET repos/{owner}/{repo}/pulls/5'
g permite 'gh api --method=GET repos/{owner}/{repo}/pulls/5'
g permite 'git status'
g permite 'git log --oneline -3'
g permite 'gh pr view 101'
g permite 'gh api repos/{owner}/{repo}/pulls/5'
g permite 'gh api -X GET repos/{owner}/{repo}/pulls/5'
g permite 'gh pr merge --help'
g bloquea 'gh pr create --title "T3: soporte de --help" --body-file b.md' 'identidad de talos-bot-leon'
g bloquea "gh pr comment 5 --body 'usa -h para ver opciones'" 'identidad de talos-bot-leon'
echo "-- con la identidad de talos-bot-leon"
extra_env=("${talos_env[@]}")
g permite 'git commit -m x'
g permite 'git push -u origin feat/x'
g permite 'gh pr create --title x --body y'
g permite 'gh pr merge 101 --squash'
g permite 'gh api repos/{owner}/{repo}/issues/5/comments -f body=x'
g permite 'gh -R leon2995/pipeline-prueba pr create --title x --body y'
g permite 'git push https://github.com/leon2995/pipeline-prueba.git feat/x'
g bloquea 'gh pr merge 102 --squash' 'ruta de gobierno CLAUDE.md'
g bloquea 'git push -u remoto-inexistente feat/x' 'no es HTTPS'
g bloquea 'git push git@github.com:leon2995/pipeline-prueba.git feat/x' 'no es HTTPS'
g bloquea 'git push https://leon2995@github.com/leon2995/pipeline-prueba.git feat/x' 'no es HTTPS'
echo "-- remoto de git push: redirecciones, texto entre comillas y opciones con valor (remoto-git-push)"
g permite 'git push'
g permite 'git push 2>&1 | tail -3'
g permite 'git push >/dev/null'
g permite 'git push origin feat/x 2>/dev/null'
g permite 'git push 2> err.txt'
g permite 'git commit -m "docs: el hook revisa git push antes del PR"'
g permite 'gh pr create --title "T4: git push con helper" --body-file b.md'
g permite "git commit -m 'git push origin feat/x'"
g permite 'git push origin feat/x -o "ci skip"'
g bloquea 'git push "git@github.com:o/r.git" feat/x' 'no es HTTPS'
g bloquea 'git push "https://leon2995@github.com/o/r.git" feat/x' 'no es HTTPS'
g bloquea 'git commit -m x && git push git@github.com:o/r.git feat/x' 'no es HTTPS'
g bloquea 'git push origin "feat/x' 'no pude leer'
g permite 'git push -o ci.skip origin feat/x'
g permite 'git push --push-option=ci.skip origin feat/x'
g permite 'git push --push-option ci.skip origin feat/x'
g bloquea 'git push -o https://github.com/o/r.git git@github.com:o/r.git feat/x' 'no es HTTPS'
g bloquea 'git push --push-option https://github.com/o/r.git git@github.com:o/r.git feat/x' 'no es HTTPS'
g bloquea 'git push --receive-pack https://github.com/o/r.git git@github.com:o/r.git feat/x' 'no es HTTPS'
g bloquea 'git push --exec https://github.com/o/r.git git@github.com:o/r.git feat/x' 'no es HTTPS'
g bloquea 'git push -uo https://github.com/o/r.git git@github.com:o/r.git feat/x' 'no es HTTPS'
g bloquea 'git push -oci.skip git@github.com:o/r.git feat/x' 'no es HTTPS'
g bloquea 'git push --receive-pack=x --exec=y git@github.com:o/r.git feat/x' 'no es HTTPS'
g permite 'git push --repo=origin'
g permite 'git push --repo origin'
g bloquea 'git push --repo git@github.com:o/r.git' 'no es HTTPS'
g bloquea 'git push --repo=https://leon2995@github.com/o/r.git' 'no es HTTPS'
g bloquea 'git push --repo=origin feat/x' 'no es HTTPS'
echo "-- identidad incompleta o de otra cuenta"
talos_base=(GH_CONFIG_DIR=/tmp/talos-gh-prueba GIT_AUTHOR_NAME=talos-bot-leon GIT_COMMITTER_NAME=talos-bot-leon FAKE_GH_LOGIN=talos-bot-leon)
extra_env=(GH_CONFIG_DIR=/tmp/talos-gh-prueba "${talos_git[@]}" GIT_AUTHOR_NAME=leon2995 GIT_COMMITTER_NAME=talos-bot-leon FAKE_GH_LOGIN=talos-bot-leon)
g bloquea 'git commit -m x' 'identidad de talos-bot-leon'
extra_env=(GH_CONFIG_DIR=/tmp/talos-gh-prueba "${talos_git[@]}" GIT_AUTHOR_NAME=talos-bot-leon GIT_COMMITTER_NAME=leon2995 FAKE_GH_LOGIN=talos-bot-leon)
g bloquea 'git commit -m x' 'identidad de talos-bot-leon'
extra_env=("${talos_git[@]}" GIT_AUTHOR_NAME=talos-bot-leon GIT_COMMITTER_NAME=talos-bot-leon FAKE_GH_LOGIN=talos-bot-leon)
g bloquea 'git push -u origin feat/x' 'identidad de talos-bot-leon'
extra_env=("${talos_base[@]}")
g bloquea 'git commit -m x' 'identidad de talos-bot-leon'
extra_env=("${talos_base[@]}" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=manager)
g bloquea 'git push -u origin feat/x' 'plantilla'
extra_env=("${talos_base[@]}" GIT_CONFIG_COUNT=2 "GIT_CONFIG_KEY_0=$clave_helper" GIT_CONFIG_VALUE_0=
  "GIT_CONFIG_KEY_1=$clave_helper" GIT_CONFIG_VALUE_1=manager)
g bloquea 'git push -u origin feat/x' 'plantilla'
extra_env=("${talos_base[@]}" GIT_CONFIG_COUNT=2 "GIT_CONFIG_KEY_1=$clave_helper" 'GIT_CONFIG_VALUE_1=!gh auth git-credential')
g bloquea 'git push -u origin feat/x' 'plantilla'
extra_env=(GH_CONFIG_DIR=/tmp/talos-gh-prueba "${talos_git[@]}" GIT_AUTHOR_NAME=talos-bot-leon GIT_COMMITTER_NAME=talos-bot-leon FAKE_GH_LOGIN=leon2995)
g bloquea 'git push -u origin feat/x' 'GitHub responde como leon2995'
g bloquea 'gh pr create --title x --body y' 'GitHub responde como leon2995'
g permite 'git commit -m x'
variante_identidad identidad-vacia ''
extra_env=("${talos_env[@]}")
g bloquea 'git commit -m x' 'identidad-agente.txt'
extra_env=()
hooks_alt=""
extra_path=""
echo "-- sin identidad-agente.txt (arranque), lo cotidiano pasa sin el entorno de talos-bot-leon"
g permite 'git commit -m x'
g permite 'git push -u origin feat/x'

echo "== CODEOWNERS: derivado de .claude/rutas-gobierno.txt (C1)"
# recortar <texto>: sin \r ni espacios al inicio y al final.
recortar() {
  local s=${1//$'\r'/}
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}
# reglas_a_codeowners <rutas-gobierno.txt>: imprime el patrón de CODEOWNERS de cada regla, con la
# misma cobertura. Falla si una regla no tiene traducción fiel (comodines o **/ con barra interna).
reglas_a_codeowners() {
  local r x
  while IFS= read -r r || [ -n "$r" ]; do
    r=$(recortar "$r")
    case "$r" in ''|'#'*) continue ;; esac
    case "${r#\*\*/}" in *'*'*) return 1 ;; esac
    case "$r" in
      '**/'*) x=${r#\*\*/}; case "${x%/}" in */*|'') return 1 ;; esac; printf '%s\n' "$x" ;;
      *) printf '/%s\n' "$r" ;;
    esac
  done < "$1"
}
# codeowners_patrones <CODEOWNERS>: imprime los patrones; falla si una línea no tiene exactamente
# el dueño @leon2995.
codeowners_patrones() {
  local l p d resto
  while IFS= read -r l || [ -n "$l" ]; do
    l=$(recortar "$l")
    case "$l" in ''|'#'*) continue ;; esac
    read -r p d resto <<< "$l"
    { [ "$d" = "@leon2995" ] && [ -z "$resto" ]; } || return 1
    printf '%s\n' "$p"
  done < "$1"
}
# comparar_codeowners <rutas-gobierno.txt> <CODEOWNERS>: sale con 0 si cubren lo mismo.
comparar_codeowners() {
  local esperado actual
  [ -f "$1" ] && [ -f "$2" ] || return 1
  esperado=$(reglas_a_codeowners "$1" | sort) || return 1
  actual=$(codeowners_patrones "$2" | sort) || return 1
  [ -n "$esperado" ] && [ "$esperado" = "$actual" ]
}
reglas="$repo/.claude/rutas-gobierno.txt"
co="$repo/.github/CODEOWNERS"
v="$tmp/codeowners"
mkdir -p "$v"
chequeo pasa 'el CODEOWNERS del repo coincide con rutas-gobierno.txt' comparar_codeowners "$reglas" "$co"
grep -v 'CLAUDE.md' "$co" > "$v/falta" 2>/dev/null
chequeo falla 'CODEOWNERS al que le falta una regla' comparar_codeowners "$reglas" "$v/falta"
{ cat "$co" 2>/dev/null; echo '/docs/ @leon2995'; } > "$v/sobra"
chequeo falla 'CODEOWNERS con una regla de más' comparar_codeowners "$reglas" "$v/sobra"
sed 's/@leon2995/@otro/' "$co" > "$v/otro" 2>/dev/null
chequeo falla 'CODEOWNERS con otro dueño' comparar_codeowners "$reglas" "$v/otro"
sed 's/@leon2995/@leon2995 @otro/' "$co" > "$v/dos" 2>/dev/null
chequeo falla 'CODEOWNERS con dos dueños' comparar_codeowners "$reglas" "$v/dos"
sed 's#^\.claude/#/.claude/#' "$co" > "$v/anclado" 2>/dev/null
chequeo falla 'CODEOWNERS con .claude/ anclado a la raíz' comparar_codeowners "$reglas" "$v/anclado"
awk '{ printf "%s\r\n", $0 }' "$co" > "$v/crlf" 2>/dev/null
chequeo pasa 'CODEOWNERS con CRLF' comparar_codeowners "$reglas" "$v/crlf"
: > "$v/vacio"
chequeo falla 'CODEOWNERS vacío' comparar_codeowners "$reglas" "$v/vacio"
chequeo falla 'CODEOWNERS ausente' comparar_codeowners "$reglas" "$v/no-existe"
printf '**/CLAUDE.md\n**/docs/adr/\n' > "$v/reglas-barra-dir"
chequeo falla 'regla **/X/ con barra interna' comparar_codeowners "$v/reglas-barra-dir" "$co"
printf '**/a/CLAUDE.md\n' > "$v/reglas-barra-archivo"
chequeo falla 'regla **/X con barra interna' comparar_codeowners "$v/reglas-barra-archivo" "$co"
printf '# solo comentarios\n' > "$v/reglas-vacias"
chequeo falla 'rutas-gobierno.txt sin reglas' comparar_codeowners "$v/reglas-vacias" "$v/vacio"

echo "== configuración: settings.json, .gitignore, plantilla y CI (C2, C5)"
s="$repo/.claude/settings.json"
# deniega <regla>: la regla está en permissions.deny de settings.json.
deniega() {
  if command -v jq >/dev/null 2>&1; then
    jq -e --arg r "$1" '.permissions.deny | index($r) != null' "$s"
  else
    grep -qF "\"$1\"" "$s"
  fi
}
for regla in 'PowerShell' 'Read(./.claude/settings.local.json)' 'Read(**/.claude/settings.local.json)' \
  'Edit(./.claude/settings.local.json)' 'Edit(**/.claude/settings.local.json)' \
  'Write(./.claude/settings.local.json)' 'Write(**/.claude/settings.local.json)' \
  'Read(~/.talos-gh/**)' 'Edit(~/.talos-gh/**)' 'Write(~/.talos-gh/**)'; do
  chequeo pasa "settings.json deniega $regla" deniega "$regla"
done
tiene_linea() { tr -d '\r' < "$2" | grep -qxF "$1"; }
chequeo pasa '.gitignore ignora .claude/settings.local.json' tiene_linea '.claude/settings.local.json' "$repo/.gitignore"
p="$repo/.claude/settings.local.example.json"
# jq es obligatorio para estos chequeos: sin jq la suite falla en lugar de saltárselos.
chequeo pasa 'jq está instalado (requerido por los chequeos de la plantilla)' command -v jq
if command -v jq >/dev/null 2>&1; then
  campo() { [ "$(jq -r --arg k "$1" '.env[$k] // "__falta__"' "$p")" = "$2" ]; }
  termina() { case "$(jq -r --arg k "$1" '.env[$k] // ""' "$p")" in *"$2") return 0 ;; esac; return 1; }
  chequeo pasa 'la plantilla es JSON válido' jq -e . "$p"
  chequeo pasa 'la plantilla apunta GH_CONFIG_DIR a ~/.talos-gh' termina GH_CONFIG_DIR '/.talos-gh'
  chequeo pasa 'la plantilla fija GIT_CONFIG_COUNT en 2' campo GIT_CONFIG_COUNT 2
  chequeo pasa 'la plantilla fija GIT_CONFIG_KEY_0' campo GIT_CONFIG_KEY_0 'credential.https://github.com.helper'
  chequeo pasa 'la plantilla vacía el helper con GIT_CONFIG_VALUE_0' campo GIT_CONFIG_VALUE_0 ''
  chequeo pasa 'la plantilla fija GIT_CONFIG_KEY_1' campo GIT_CONFIG_KEY_1 'credential.https://github.com.helper'
  chequeo pasa 'la plantilla usa gh como helper en GIT_CONFIG_VALUE_1' campo GIT_CONFIG_VALUE_1 '!gh auth git-credential'
  chequeo pasa 'la plantilla fija el autor talos-bot-leon' campo GIT_AUTHOR_NAME talos-bot-leon
  chequeo pasa 'la plantilla fija el committer talos-bot-leon' campo GIT_COMMITTER_NAME talos-bot-leon
  chequeo pasa 'la plantilla usa el email noreply del autor' campo GIT_AUTHOR_EMAIL '335185800+talos-bot-leon@users.noreply.github.com'
  chequeo pasa 'la plantilla usa el email noreply del committer' campo GIT_COMMITTER_EMAIL '335185800+talos-bot-leon@users.noreply.github.com'
fi
chequeo falla 'la plantilla no trae prefijos de token' grep -qE 'ghp_|gho_|ghu_|ghs_|ghr_|github_pat_' "$p"
ci="$repo/.github/workflows/ci.yml"
# bloque_yaml <archivo> <clave> <sangría>: imprime las líneas de esa clave del YAML, sin
# comentarios, hasta la próxima clave con la misma sangría o menos.
bloque_yaml() {
  tr -d '\r' < "$1" | awk -v k="$3$2:" -v n="${#3}" '
    $0 == k { dentro = 1; next }
    dentro && /^[[:space:]]*#/ { next }
    dentro && /[^[:space:]]/ { match($0, /^ */); if (RLENGTH <= n) exit; print }'
}
job_hooks() { bloque_yaml "$ci" hooks '  '; }
disparadores() { bloque_yaml "$ci" on ''; }
# push dentro de on: (un filtro de ramas bajo pull_request filtraría ramas base, no pushes).
disparador_push() { disparadores | awk '/^  push:$/ { d = 1; next } d && /^  [^ ]/ { exit } d'; }
en_bloque() { "$1" | grep -qE "$2"; }
chequeo pasa 'el job hooks corre en ubuntu-latest' en_bloque job_hooks '^    runs-on: ubuntu-latest$'
chequeo pasa 'el job hooks corre la suite' en_bloque job_hooks '^      - run: bash scripts/test-hooks.sh$'
chequeo pasa 'el job hooks corre la suite con mawk' en_bloque job_hooks 'PATH="/tmp/con-mawk:\$PATH" bash scripts/test-hooks.sh'
chequeo pasa 'el job hooks instala mawk si falta (no lo omite)' en_bloque job_hooks 'apt-get install -y[a-z -]* mawk'
chequeo pasa 'CI corre en pull_request' en_bloque disparadores '^  pull_request:'
chequeo pasa 'CI corre en push a feat/** y fix/** (bajo push:)' en_bloque disparador_push "^    branches: \[.*'feat/\*\*'.*'fix/\*\*'.*\]"

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
