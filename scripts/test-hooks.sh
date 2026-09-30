#!/usr/bin/env bash
# Prueba los hooks de .claude/hooks: les pasa por stdin el JSON que manda Claude Code y
# verifica el código de salida (2 = bloquea, 0 = permite). Termina con 1 si algún caso falla.
# Uso: bash scripts/test-hooks.sh
set -uo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
# Configuración del framework (T3a): el dueño, el bot y su email salen de .claude/pipeline.conf
# (líneas clave=valor), no de valores fijos. Así la suite corre igual en otro repo con otro conf.
conf() { sed -n "s/^$1=//p" "$repo/.claude/pipeline.conf" 2>/dev/null | tr -d '\r' | head -1; }
dueno=$(conf dueno)
bot=$(conf bot)
bot_email=$(conf bot_email)
# Organización donde el agente crea repos y equipo obligatorio (A1).
org=$(conf org)
equipo=$(conf equipo)
ok=0
fallos=0
extra_path=""   # se antepone al PATH del hook; sirve para simular herramientas rotas o un gh falso
hooks_alt=""    # si no está vacío, se corre el hook de este directorio (copia) en lugar del base
extra_env=()    # variables de entorno para el hook (por ejemplo la identidad del bot)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# La suite corre sobre una copia de los hooks y de rutas-gobierno.txt, sin identidad-agente.txt:
# el resultado no depende de que la identidad del agente esté activada en el repo (C4).
mkdir -p "$tmp/base/.claude/hooks"
cp "$repo"/.claude/hooks/*.sh "$tmp/base/.claude/hooks/"
cp "$repo/.claude/rutas-gobierno.txt" "$tmp/base/.claude/" 2>/dev/null
cp "$repo/.claude/pipeline.conf" "$tmp/base/.claude/" 2>/dev/null
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
    -u GIT_COMMITTER_NAME -u GH_TOKEN -u GITHUB_TOKEN -u FAKE_GH_LOGIN -u RAILWAY_TOKEN \
    -u RAILWAY_API_TOKEN ${extra_env[@]+"${extra_env[@]}"} \
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
  137) rutas=(.gitleaksignore) ;;
  138) rutas=(.gitleaks.toml) ;;
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
g bloquea 'gh pr merge 137 --squash' 'ruta de gobierno .gitleaksignore'
g bloquea 'gh pr merge 138 --squash' 'ruta de gobierno .gitleaks.toml'
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
  cp "$hooks/../pipeline.conf" "$tmp/reglas/$1/.claude/" 2>/dev/null
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
g bloquea 'git credential reject' 'credenciales'
g bloquea 'printf x | git credential fill' 'credenciales'
g bloquea 'git -C . credential fill' 'credenciales'
# git credential-manager (lecciones, T2): el agente no toca el Credential Manager de Leonardo; solo
# puede listar las cuentas.
g bloquea 'git credential-manager github logout leon2995' 'credenciales'
g bloquea 'git credential-manager github login --username leon2995 --device' 'credenciales'
g bloquea 'git credential-manager get' 'credenciales'
g bloquea 'git credential-manager store' 'credenciales'
g bloquea 'git credential-manager erase' 'credenciales'
g bloquea 'git credential-manager configure' 'credenciales'
g bloquea 'git credential-manager' 'credenciales'
g bloquea 'git-credential-manager github logout x' 'credenciales'
g bloquea 'git-credential-manager.exe github logout x' 'credenciales'
g bloquea 'git -C . credential-manager github logout x' 'credenciales'
g bloquea 'git credential-manager github list; git credential-manager github logout x' 'credenciales'
# Después de la ronda del auditor: && entre invocaciones, un comentario que cuela github list, -core,
# ruta completa y -c antes del subcomando.
g bloquea 'git credential-manager github list && git credential-manager github logout x' 'credenciales'
g bloquea 'git credential-manager github logout x # git credential-manager github list' 'credenciales'
g bloquea 'git credential-manager-core erase' 'credenciales'
g bloquea 'git-credential-manager-core github logout x' 'credenciales'
g bloquea '/mingw64/bin/git-credential-manager.exe github logout x' 'credenciales'
g bloquea 'git -c core.x=y credential-manager erase' 'credenciales'
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
g permite 'git credential-manager github list'
g permite 'git credential-manager github list --url https://github.com'
g permite 'git credential-manager github list 2>&1 | head -3'
g permite 'git grep -n credential-manager SETUP.md'
g permite 'git log -S credential-manager --oneline'

echo "== guard-commands.sh: Railway, solo lecturas (T3a)"
for c in 'railway --help' 'railway -V' 'railway --version' 'railway help up' 'railway up --help' \
  'railway status' 'railway status --json' 'railway whoami' 'railway logs' 'railway logs | tail -n 200' \
  'railway list' 'railway ls' 'railway metrics' 'railway docs' 'railway environment link staging' \
  'railway environment list' 'railway env ls' 'railway environment config' 'railway environment link production' \
  'railway service list' 'railway service status' 'railway service logs' 'railway domain list' \
  'railway domain status x.up.railway.app' 'railway deployment list' 'railway project list' 'railway volume list' \
  'railway variables --kv | cut -d= -f1' 'railway variable list --kv | cut -d= -f1' 'railway vars --kv | cut -d= -f1' \
  'railway usage' 'railway usage projects' 'railway api schema' 'railway api search deployment' \
  'railway api describe Service' 'railway config plan' 'railway config plan --detailed-exit-code' \
  'railway config migrate' 'railway.exe status' '/usr/local/bin/railway status' 'npx @railway/cli status' \
  'npx -y @railway/cli logs' 'NO_COLOR=1 railway status' '(railway status)' 'grep -rn railway SETUP.md' \
  'cat .railway/railway.ts' 'echo railway up' 'ls .railway' \
  'if railway status; then echo ok; fi' 'for i in 1 2; do railway logs; done' 'timeout 30 railway status' \
  'railway ssh --help' 'railway run --help' 'railway variable set --help'; do
  g permite "$c"
done
for c in 'railway up' 'railway up --detach' 'railway redeploy' 'railway restart' 'railway down' 'railway deploy -t x' \
  'railway add --repo o/r' 'railway init --name x' 'railway link' 'railway unlink' 'railway login' 'railway logout' \
  'railway run npm start' 'railway shell' 'railway ssh' 'railway connect postgres' 'railway domain' \
  'railway domain --port 8080' 'railway domain delete x.up.railway.app' 'railway environment new staging' \
  'railway env delete staging' 'railway environment edit' 'railway service redeploy' 'railway service web' \
  'railway variable set FOO=1' 'railway variables set FOO=1' 'railway var delete FOO' 'railway volume add' \
  'railway project delete' 'railway delete' 'railway config apply' 'railway config pull' 'railway config init' \
  'railway config plan --show-values' 'railway config plan --decrypt-variables' 'railway config migrate --apply' \
  'railway config migrate --delete-files' 'railway usage limit set 50' "railway api 'mutation { x }'" \
  "railway api 'query { me { id } }'" 'railway mcp' 'railway setup agent -y' 'railway upgrade --yes' \
  'railway.exe up' '/usr/local/bin/railway up' 'npx @railway/cli up' 'npx -y @railway/cli redeploy' \
  'NO_COLOR=1 railway up' '(railway up)' 'git status && railway up' 'railway status; railway down' \
  'railway environment staging' 'railway env production' \
  'for i in 1 2 3; do railway up --detach && break; sleep 10; done' 'if ! railway up; then echo fallo; fi' \
  'then railway redeploy' '{ railway down; }' 'while true; do railway restart; done' 'timeout 600 railway up' \
  'xargs -n 1 railway up' 'nice -n 10 railway up' 'time railway up' 'watch -n 5 railway redeploy' \
  'railway ssh -- df -h' 'railway ssh free -h' 'railway run -- node x.js --help' 'railway run pytest -V'; do
  g bloquea "$c" 'Railway'
done
g bloquea 'railway variables --kv' 'solo nombres'
g bloquea 'railway vars --kv' 'solo nombres'

echo "== guard-commands.sh: sesión de Railway de Leonardo (T3a)"
g bloquea 'cat ~/.railway/config.json' 'credenciales'
g bloquea 'ls ~/.railway' 'credenciales'
g bloquea 'cat $HOME/.railway/config.json' 'credenciales'
g bloquea 'cat ${HOME}/.railway/config.json' 'credenciales'
g bloquea 'type C:/Users/dev/.railway/config.json' 'credenciales'
g bloquea 'ls /c/Users/dev/.railway' 'credenciales'
g bloquea 'grep token .railway/config.json' 'credenciales'
g bloquea 'echo $RAILWAY_TOKEN' 'credenciales'
g bloquea 'RAILWAY_API_TOKEN=x railway status' 'credenciales'
g bloquea 'cat "C:\Users\dev\.railway\config.json"' 'credenciales'
g bloquea 'ls /home/dev/.railway' 'credenciales'
g bloquea 'dir %USERPROFILE%\.railway' 'credenciales'
g bloquea 'ls $USERPROFILE/.railway' 'credenciales'
g permite 'cat .railway/railway.ts'
g permite 'ls C:/Users/dev/proyectos/app/.railway'
g permite 'cat $USERPROFILE/proyectos/app/.railway/railway.ts'
g permite 'echo $USERPROFILE'

# repo_prueba <dir> <url de origin> [con-codeowners]: repo git de prueba con un commit y
# refs/remotes/origin/main en ese commit. Con con-codeowners, el commit trae .github/CODEOWNERS.
repo_prueba() {
  mkdir -p "$1" && git -C "$1" init -q 2>/dev/null
  git -C "$1" remote add origin "$2"
  if [ "${3:-}" = con-codeowners ]; then
    mkdir -p "$1/.github"
    printf '* @%s\n' "$dueno" > "$1/.github/CODEOWNERS"
  else
    printf 'x\n' > "$1/README.md"
  fi
  git -C "$1" add -A
  git -C "$1" -c user.name=prueba -c user.email=prueba@example.com commit -qm inicial
  git -C "$1" update-ref refs/remotes/origin/main HEAD
}
repo_prueba "$tmp/dir con espacio" https://github.com/o/r.git
repo_prueba "$tmp/dir-ssh" git@github.com:o/r.git
repo_prueba "$tmp/con-codeowners" https://github.com/o/r.git con-codeowners
repo_prueba "$tmp/sin-codeowners" https://github.com/o/r.git

echo "== guard-commands.sh: identidad del bot $bot (C4), con copia del hook y gh falso"
# variante_identidad <nombre> <contenido>: copia del hook con .claude/identidad-agente.txt.
variante_identidad() {
  variante "$1"
  cp "$hooks/../rutas-gobierno.txt" "$tmp/reglas/$1/.claude/" 2>/dev/null
  printf '%s\n' "$2" > "$tmp/reglas/$1/.claude/identidad-agente.txt"
}
# Identidad completa del bot, igual que la plantilla (sin token: el gh falso responde api user).
clave_helper='credential.https://github.com.helper'
talos_git=(GIT_CONFIG_COUNT=2 "GIT_CONFIG_KEY_0=$clave_helper" GIT_CONFIG_VALUE_0=
  "GIT_CONFIG_KEY_1=$clave_helper" 'GIT_CONFIG_VALUE_1=!gh auth git-credential')
talos_env=(GH_CONFIG_DIR=/tmp/talos-gh-prueba "${talos_git[@]}" GIT_AUTHOR_NAME="$bot"
  GIT_COMMITTER_NAME="$bot" FAKE_GH_LOGIN="$bot")
extra_path="$tmp/gh-falso:"
variante_identidad identidad "$bot"
echo "-- sin la identidad de $bot"
extra_env=()
g bloquea 'git commit -m x' "identidad de $bot"
g bloquea 'git push -u origin feat/x' "identidad de $bot"
g bloquea 'gh pr create --title x --body y' "identidad de $bot"
g bloquea 'gh pr merge 101 --squash' "identidad de $bot"
g bloquea 'gh pr comment 101 --body x' "identidad de $bot"
g bloquea 'gh api repos/{owner}/{repo}/issues/5/comments -f body=x' "identidad de $bot"
g bloquea 'gh api graphql -f query=x' "identidad de $bot"
g bloquea 'gh api -X PATCH repos/{owner}/{repo}/pulls/5 --input datos.json' "identidad de $bot"
g bloquea 'gh api --method DELETE repos/{owner}/{repo}/git/refs/heads/x' "identidad de $bot"
g bloquea 'gh pr create --title x --body y; gh pr view --help' "identidad de $bot"
g bloquea 'gh pr new --fill' "identidad de $bot"
g bloquea 'gh -R leon2995/pipeline-prueba pr create --title x --body y' "identidad de $bot"
g bloquea 'gh pr -R leon2995/pipeline-prueba edit 5 --title x' "identidad de $bot"
g bloquea 'gh pr edit 5 --title x' "identidad de $bot"
g bloquea 'gh pr close 5' "identidad de $bot"
g bloquea 'gh pr reopen 5' "identidad de $bot"
g bloquea 'gh pr ready 5' "identidad de $bot"
g bloquea 'gh pr review 5 --comment -b x' "identidad de $bot"
g bloquea 'gh api repos/{owner}/{repo}/issues/1 -X GET -X DELETE' "identidad de $bot"
g bloquea 'gh api repos/{owner}/{repo}/issues/1 -X DELETE -X GET' "identidad de $bot"
g bloquea 'gh api -X "POST" repos/{owner}/{repo}/issues/5/comments' "identidad de $bot"
g bloquea 'gh api -X GET repos/{owner}/{repo}/pulls/5; gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/x' "identidad de $bot"
g bloquea 'gh --repo leon2995/pipeline-prueba api repos/{owner}/{repo}/issues -f title=x' "identidad de $bot"
g bloquea 'git -C . push -u origin feat/x' "identidad de $bot"
# gh repo que escribe cuenta para C4 (A1, C6); en gh repo create y edit, -h es --homepage, no ayuda.
g bloquea "gh repo create $org/app --private --team $equipo" "identidad de $bot"
g bloquea "gh repo new $org/app --private --team $equipo" "identidad de $bot"
g bloquea "gh repo edit $org/app --description x" "identidad de $bot"
g bloquea "gh repo edit $org/app -h https://x.cl" "identidad de $bot"
g bloquea "gh repo rename nuevo -R $org/app --yes" "identidad de $bot"
g bloquea "gh repo archive $org/app --yes" "identidad de $bot"
g bloquea "gh repo unarchive $org/app --yes" "identidad de $bot"
g bloquea 'gh repo sync' "identidad de $bot"
g bloquea 'git.exe commit -m x' "identidad de $bot"
g bloquea '/usr/bin/git push -u origin feat/x' "identidad de $bot"
g permite 'gh repo create --help'
g permite "gh repo view $org/app --json visibility"
g permite 'gh api -XGET repos/{owner}/{repo}/pulls/5'
g permite 'gh api --method=GET repos/{owner}/{repo}/pulls/5'
g permite 'git status'
g permite 'git log --oneline -3'
g permite 'gh pr view 101'
g permite 'gh api repos/{owner}/{repo}/pulls/5'
g permite 'gh api -X GET repos/{owner}/{repo}/pulls/5'
g permite 'gh pr merge --help'
g bloquea 'gh pr create --title "T3: soporte de --help" --body-file b.md' "identidad de $bot"
g bloquea "gh pr comment 5 --body 'usa -h para ver opciones'" "identidad de $bot"
echo "-- con la identidad de $bot"
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
g permite "gh repo create $org/app --private --team $equipo"
g permite "gh repo edit $org/app -h https://x.cl"
g bloquea "gh repo create $org/app --public --team $equipo" '(repos)'
echo "-- git -C <dir> push: el remoto se resuelve en <dir> (A1, C6)"
g permite "git -C \"$tmp/dir con espacio\" push origin feat/x"
g bloquea "git -C \"$tmp/dir-ssh\" push origin feat/x" 'no es HTTPS'
g bloquea "git -C $tmp/dir-ssh push -u origin feat/x" 'no es HTTPS'
g bloquea "git -C \"$tmp/no-existe\" push origin feat/x" 'no existe'
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
g permite 'git -C . push -u origin feat/x'
g permite 'git -c core.x=y push origin feat/x'
g bloquea 'git -C . push git@github.com:o/r.git feat/x' 'no es HTTPS'
g permite '(cd . && git push)'
g permite '(git push origin feat/x)'
g bloquea '(git push git@github.com:o/r.git feat/x)' 'no es HTTPS'
echo "-- identidad incompleta o de otra cuenta"
talos_base=(GH_CONFIG_DIR=/tmp/talos-gh-prueba GIT_AUTHOR_NAME="$bot" GIT_COMMITTER_NAME="$bot" FAKE_GH_LOGIN="$bot")
extra_env=(GH_CONFIG_DIR=/tmp/talos-gh-prueba "${talos_git[@]}" GIT_AUTHOR_NAME="$dueno" GIT_COMMITTER_NAME="$bot" FAKE_GH_LOGIN="$bot")
g bloquea 'git commit -m x' "identidad de $bot"
extra_env=(GH_CONFIG_DIR=/tmp/talos-gh-prueba "${talos_git[@]}" GIT_AUTHOR_NAME="$bot" GIT_COMMITTER_NAME="$dueno" FAKE_GH_LOGIN="$bot")
g bloquea 'git commit -m x' "identidad de $bot"
extra_env=("${talos_git[@]}" GIT_AUTHOR_NAME="$bot" GIT_COMMITTER_NAME="$bot" FAKE_GH_LOGIN="$bot")
g bloquea 'git push -u origin feat/x' "identidad de $bot"
extra_env=("${talos_base[@]}")
g bloquea 'git commit -m x' "identidad de $bot"
extra_env=("${talos_base[@]}" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=manager)
g bloquea 'git push -u origin feat/x' 'plantilla'
extra_env=("${talos_base[@]}" GIT_CONFIG_COUNT=2 "GIT_CONFIG_KEY_0=$clave_helper" GIT_CONFIG_VALUE_0=
  "GIT_CONFIG_KEY_1=$clave_helper" GIT_CONFIG_VALUE_1=manager)
g bloquea 'git push -u origin feat/x' 'plantilla'
extra_env=("${talos_base[@]}" GIT_CONFIG_COUNT=2 "GIT_CONFIG_KEY_1=$clave_helper" 'GIT_CONFIG_VALUE_1=!gh auth git-credential')
g bloquea 'git push -u origin feat/x' 'plantilla'
extra_env=(GH_CONFIG_DIR=/tmp/talos-gh-prueba "${talos_git[@]}" GIT_AUTHOR_NAME="$bot" GIT_COMMITTER_NAME="$bot" FAKE_GH_LOGIN="$dueno")
g bloquea 'git push -u origin feat/x' "GitHub responde como $dueno"
g bloquea 'gh pr create --title x --body y' "GitHub responde como $dueno"
g permite 'git commit -m x'
variante_identidad identidad-vacia ''
extra_env=("${talos_env[@]}")
g bloquea 'git commit -m x' 'identidad-agente.txt'
extra_env=()
hooks_alt=""
extra_path=""
echo "-- sin identidad-agente.txt (arranque), lo cotidiano pasa sin el entorno de $bot"
g permite 'git commit -m x'
g permite 'git push -u origin feat/x'

echo "== guard-commands.sh: repos en la organización $org (A1)"
org_may=$(printf '%s' "$org" | tr '[:lower:]' '[:upper:]')
equipo_may=$(printf '%s' "$equipo" | tr '[:lower:]' '[:upper:]')
echo "-- gh repo create: solo $org/<nombre>, --private y --team $equipo (C1)"
for c in \
  "gh repo create $org/app --private --team $equipo" \
  "gh repo new $org/app --private --team $equipo" \
  "gh repo create $org/app --private -t $equipo --add-readme" \
  "gh repo create $org/app --team=$equipo --private --add-readme --disable-wiki --disable-issues" \
  "gh repo create $org_may/App.v2_x --private --team $equipo_may" \
  "gh repo create $org/app --private --team $equipo -d \"API; v1 & más\"" \
  "gh repo create $org/app --private --team $equipo --description='x --public y'" \
  "gh repo create $org/app --private --team $equipo -g Node -l mit" \
  "gh repo create $org/app --private --team $equipo --gitignore=Node --license=mit" \
  "gh repo create $org/app --private --team $equipo 2>&1 | tail -3" \
  "gh repo create $org/app --private --team $equipo > salida.txt" \
  'gh repo create --help' 'gh repo new --help'; do
  g permite "$c"
done
for c in \
  "gh repo create $org/app --public --team $equipo" \
  "gh repo new $org/app --public --team $equipo" \
  "gh repo create $org/app --team $equipo" \
  'gh repo create' \
  'gh repo new' \
  "gh repo create $org/app --internal --private --team $equipo" \
  "gh repo create $org/app --private=false --team $equipo" \
  "gh repo create $org/app --private=true --team $equipo" \
  "gh repo create $org/app --private --private --team $equipo" \
  "gh repo create $org/app --private --public --team $equipo" \
  "gh repo create $org/app --private --public=false --team $equipo" \
  "gh repo create app --private --team $equipo" \
  "gh repo create $bot/app --private --team $equipo" \
  "gh repo create $dueno/app --private --team $equipo" \
  "gh repo create otra-org/app --private --team $equipo" \
  "gh repo create $org-x/app --private --team $equipo" \
  "gh repo create github.com/$org/app --private --team $equipo" \
  "gh repo create https://github.com/$org/app --private --team $equipo" \
  "gh repo create $org/. --private --team $equipo" \
  "gh repo create $org/.. --private --team $equipo" \
  "gh repo create $org/a/b --private --team $equipo" \
  "gh repo create $org/ --private --team $equipo" \
  "gh repo create $org/app otra --private --team $equipo" \
  "gh repo create --private --team $equipo --source=. --push" \
  "gh repo create $org/app --private --team $equipo --source=. --push" \
  "gh repo create $org/app --private --team $equipo -s . --push" \
  "gh repo create $org/app --private --team $equipo --clone" \
  "gh repo create $org/app --private --team $equipo -c" \
  "gh repo create $org/app --private --team $equipo -r origin" \
  "gh repo create $org/app --private --team $equipo --remote=origin" \
  "gh repo create $org/app --private --team $equipo -p $org/plantilla" \
  "gh repo create $org/app --private --team $equipo --template $org/plantilla --include-all-branches" \
  "gh repo create $org/app --private --team $equipo -h https://x.cl" \
  "gh repo create $org/app --private --team $equipo --homepage https://x.cl" \
  "gh repo create $org/app --private --team $equipo --otra-opcion" \
  "gh repo create $org/app --private --team $equipo -dx" \
  "gh repo create $org/app --private --team $equipo -d=x" \
  "gh repo create $org/app --private --team $equipo --add-readme=false" \
  "gh repo create $org/app --private --team $equipo -- --public" \
  "gh repo create $org/app --private --team $equipo -d" \
  "gh repo create $org/app --private" \
  "gh repo create $org/app --private --team otro-equipo" \
  "gh repo create $org/app --private -t otro-equipo" \
  "gh repo create $org/app --private --team=otro-equipo" \
  "gh repo create $org/app --private --team $equipo --team otro" \
  "gh repo create $org/app --private --team $equipo --team $equipo" \
  "gh repo create $org/app --private --team" \
  "gh repo create \"\$N\" --private --team $equipo" \
  "gh repo create $org/\$N --private --team $equipo" \
  "gh repo create $org/\`n\` --private --team $equipo" \
  "gh repo create $org/app --private --team \$E" \
  "gh repo create $org/app --private --team $equipo -d \"sin cerrar" \
  "GH_HOST=x gh repo create $org/app --private --team $equipo" \
  "GH_REPO=$org/app gh repo create $org/app --private --team $equipo" \
  "gh repo create $org/a --private --team $equipo && gh repo create $org/b --private --team $equipo" \
  "gh repo create $org/a --private --team $equipo; gh repo new $org/b --private --team $equipo" \
  "bash -c \"gh repo create $org/app --public\"" \
  "bash -c 'gh repo create $org/app --private --team $equipo'" \
  "eval gh repo create $org/app --public" \
  "gh.exe repo create $org/app --public" \
  "/usr/bin/gh repo create $org/app --public" \
  "echo \"\$(gh repo create $org/app --public)\"" \
  "x=\$(gh repo create $org/app --public)" \
  "(gh repo create $org/app --public)" \
  "gh repo create $org/app --public # gh repo create $org/app --private --team $equipo"; do
  g bloquea "$c" '(repos)'
done
echo "-- gh repo edit: sin visibilidad, rama por defecto ni forks (C2)"
for c in \
  "gh repo edit $org/app --description x" \
  "gh repo edit $org/app --delete-branch-on-merge --enable-squash-merge" \
  "gh repo edit $org/app --allow-forking=false" \
  "gh repo edit $org/app -h https://x.cl" \
  "gh repo edit --enable-auto-merge=false" \
  "gh repo edit $org/app -d \"no usar --visibility aquí\"" \
  'gh repo edit --help'; do
  g permite "$c"
done
for c in \
  "gh repo edit $org/app --visibility public --accept-visibility-change-consequences" \
  'gh repo edit --visibility=private --accept-visibility-change-consequences' \
  "gh repo edit $org/app --visibility private" \
  "gh repo edit $org/app --visibility=internal" \
  "gh repo edit $org/app --accept-visibility-change-consequences" \
  "gh repo edit $org/app --accept-visibility-change-consequences=true" \
  "gh repo edit $org/app --default-branch staging" \
  "gh repo edit $org/app --default-branch=staging" \
  "gh repo edit $org/app --allow-forking" \
  "gh repo edit $org/app --allow-forking=true" \
  'gh repo edit' \
  "gh repo edit $org/app" \
  "gh repo edit $org/app -d x --visibility public" \
  "bash -c \"gh repo edit $org/app --visibility public\""; do
  g bloquea "$c" '(repos)'
done
echo "-- fork, delete, deploy keys, alias y extensiones (C3)"
for c in \
  "gh repo fork cli/cli --org $org" \
  'gh repo fork' \
  "gh repo fork $org/app --clone" \
  "gh repo delete $org/app --yes" \
  'gh repo delete' \
  "gh repo deploy-key add k.pub -R $org/app" \
  "gh repo deploy-key add k.pub -R $org/app --allow-write" \
  "gh alias set rc 'repo create --public'" \
  'gh alias import alias.yml' \
  'gh extension install x/gh-y' \
  'gh ext install x/gh-y' \
  'gh extensions upgrade --all' \
  'gh extension exec y' \
  "bash -c 'gh alias set x y'"; do
  g bloquea "$c" '(repos)'
done
for c in \
  "gh repo view $org/app --json visibility" \
  "gh repo list $org --visibility public --limit 1000 --json nameWithOwner" \
  "gh repo list $bot --visibility public --json nameWithOwner --jq '.[].nameWithOwner'" \
  "gh repo clone $org/app" \
  "gh repo deploy-key list -R $org/app" \
  "gh repo rename nuevo -R $org/app --yes" \
  "gh repo archive $org/app --yes" \
  'gh repo view --help' \
  'gh alias list' \
  'gh extension list' \
  'gh ext list'; do
  g permite "$c"
done
echo "-- gh api de escritura hacia creación, visibilidad o exposición del repo (C4)"
for c in \
  "gh api -X PATCH repos/$org/app -f visibility=public" \
  "gh api --method=patch /repos/$org/app -F private=false" \
  "gh api -XPATCH 'repos/{owner}/{repo}' --input body.json" \
  "gh api https://api.github.com/repos/$org/app -X PATCH -f visibility=public" \
  "gh api repos/$org/APP -X Patch -f visibility=public" \
  "gh api -X DELETE repos/$org/app" \
  "gh api -X PUT repos/$org/app -f x=1" \
  "gh api -X \"\$M\" repos/$org/app" \
  "gh api --method GET repos/$org/app -X DELETE" \
  "gh api orgs/$org/repos -f name=app -F private=true" \
  "gh api 'orgs/$org/repos?a=1&b=2' -X POST -f name=x" \
  "gh api user/repos -f name=app" \
  "gh api /user/repos -X POST -f name=app -F private=true" \
  'gh api -X POST user/codespaces/abc/publish -f name=app' \
  "gh api repos/$org/plantilla/generate -f owner=$org -f name=app" \
  "gh api -X POST repos/cli/cli/forks -f organization=$org" \
  "gh api repos/$org/app/transfer -f new_owner=$bot" \
  "gh api -X POST repos/$org/app/pages -f 'source[branch]=main'" \
  "gh api -X PUT repos/$org/app/pages -f cname=x" \
  "gh api -X PUT repos/$org/app/collaborators/alguien -f permission=push" \
  "gh api -X PATCH repos/$org/app/invitations/5 -f permissions=admin" \
  "gh api repos/$org/app/keys -f key=x -F read_only=false" \
  "gh api repos/$org/app/hooks -f name=web" \
  "gh api repos/$org/app/rulesets --input r.json" \
  "gh api -X POST repos/$org/app/git/refs -f ref=refs/heads/staging -f sha=abc" \
  "gh api -X PATCH repos/$org/app/git/refs/heads/staging -f sha=abc" \
  "gh api -X POST repos/$org/app/branches/staging/rename -f new_name=x" \
  "gh api -X DELETE repos/$org/app/branches/main/protection" \
  "gh api -X PUT repos/$org/app/branches/main/protection --input p.json" \
  "gh api -X PATCH orgs/$org -F members_can_create_pages=true" \
  "gh api -X PATCH orgs/$org/teams/$equipo -f privacy=closed" \
  "gh api -X PUT orgs/$org/teams/$equipo/repos/$org/app -f permission=admin" \
  "gh api orgs/$org/rulesets --input r.json" \
  "gh api -X PUT orgs/$org/rulesets/1 --input r.json" \
  "gh api -X POST \"\$URL\" -f x=1" \
  'gh api -f x=1' \
  "gh api -X POST repos/$org/app/issues extra -f x=1" \
  "gh api graphql -f query='mutation{createRepository(input:{name:\"app\",visibility:PUBLIC}){repository{url}}}'" \
  "gh api graphql -f 'query=Mutation { updateTeam }'" \
  'gh api graphql -F query=@m.graphql' \
  'gh api graphql -Fquery=@m.graphql' \
  'gh api graphql --input q.json' \
  "bash -c \"gh api -X PATCH repos/$org/app -f visibility=public\"" \
  "echo \"\$(gh api -X DELETE repos/o/r)\""; do
  g bloquea "$c" '(repos)'
done
for c in \
  "gh api repos/$org/app --jq .visibility" \
  "gh api -X GET repos/$org/app" \
  "gh api \"orgs/$org/repos?type=public&per_page=100\" --paginate --jq '.[].full_name'" \
  "gh api orgs/$org/rulesets" \
  "gh api repos/$org/app/rules/branches/main" \
  "gh api -X GET repos/$org/app/pages" \
  "gh api repos/$org/app/branches/main --jq .commit.sha" \
  "sha=\$(gh api repos/$org/app/branches/main --jq .commit.sha)" \
  "gh api graphql -f query='query{organization(login:\"x\"){repositories(first:1,privacy:PUBLIC){nodes{nameWithOwner}}}}'" \
  'gh api repos/{owner}/{repo}/issues/5/comments -f body=x' \
  'gh api -X PATCH repos/{owner}/{repo}/pulls/5 -f title=x' \
  "gh api repos/{owner}/{repo}/pulls/5/files --paginate --jq '.[].filename'" \
  "gh api -X POST repos/{owner}/{repo}/pulls/5/requested_reviewers -f 'reviewers[]=$dueno'" \
  'gh api --help'; do
  g permite "$c"
done
echo "-- red textual: el texto de gh repo o gh api dentro de un --title o un -m también bloquea (C5, costo aceptado)"
g bloquea 'gh pr create --title "usa gh repo create" --body-file b.md' '(repos)'
g bloquea 'git commit -m "llama a gh api"' '(repos)'
g permite 'gh pr create --title "repos privados en la organización" --body-file b.md'
echo "-- pipeline.conf sin org o sin equipo (C8)"
variante sin-org
printf 'dueno=%s\nbot=%s\nequipo=%s\n' "$dueno" "$bot" "$equipo" > "$tmp/reglas/sin-org/.claude/pipeline.conf"
g bloquea "gh repo create $org/app --private --team $equipo" 'pipeline.conf'
variante sin-equipo
printf 'dueno=%s\nbot=%s\norg=%s\n' "$dueno" "$bot" "$org" > "$tmp/reglas/sin-equipo/.claude/pipeline.conf"
g bloquea "gh repo create $org/app --private --team $equipo" 'pipeline.conf'
hooks_alt=""
echo "-- rama staging: solo desde origin/main y con CODEOWNERS (C7)"
g permite "git -C $tmp/con-codeowners push origin origin/main:refs/heads/staging"
g permite "git -C $tmp/con-codeowners push origin origin/main:staging"
g permite "git -C \"$tmp/con-codeowners\" push origin 'origin/main:refs/heads/staging'"
for c in \
  "git -C $tmp/sin-codeowners push origin origin/main:refs/heads/staging" \
  "git -C $tmp/sin-codeowners push origin origin/main:staging" \
  "git -C $tmp/no-existe push origin origin/main:staging" \
  "git -C $tmp/con-codeowners push otro origin/main:staging" \
  "git -C $tmp/con-codeowners push origin HEAD:staging" \
  'git push origin staging' \
  'git push origin "staging"' \
  'git push -u origin staging' \
  'git push origin HEAD:staging' \
  'git push origin feat/x:refs/heads/staging' \
  'git push origin feat/x:STAGING' \
  'git push -u origin feat/x staging' \
  'git push origin origin/feat:staging' \
  'git push origin main:staging'; do
  g bloquea "$c" '(staging)'
done
for c in 'git push --all origin' 'git push --all' 'git push --branches origin' 'git push --al origin' \
  "git push origin 'refs/heads/*:refs/heads/*'" 'git push origin "*:*"'; do
  g bloquea "$c" 'todas las ramas'
done
for c in 'git push origin feat/staging-fix' 'git push origin staging:feat/x' 'git push --atomic origin feat/x' \
  'git push -u origin fix/staging' 'git push --tags origin'; do
  g permite "$c"
done
echo "-- después de la ronda del auditor: rutas de Windows, deploy-key -R, continuación de línea y GraphQL en variables"
for c in \
  "\"C:\\Program Files\\GitHub CLI\\gh.exe\" repo create $org/x --public" \
  "C:\\tools\\gh.exe repo create $org/x --public" \
  "\"C:\\Program Files\\GitHub CLI\\gh.exe\" api -X PATCH repos/$org/x -f visibility=public" \
  "gh repo deploy-key -R $org/x add k.pub" \
  "gh repo deploy-key --repo $org/x add k.pub" \
  "gh repo deploy-key -R $org/x" \
  "gh repo create $org/app \\
  --public --team $equipo" \
  "gh \\
  repo create $org/app --public" \
  "Q=\"mutation{updateRepository(input:{repositoryId:\\\"x\\\"}){clientMutationId}}\"; gh api graphql -f query=\"\$Q\"" \
  "gh api graphql -f query=\"\$Q\"" \
  "gh api graphql -f query=\"\$(cat m.graphql)\"" \
  "gh api graphql -f query=\`cat m.graphql\`" \
  "gh api -X POST repos/$org/x/branches/feat/y/rename -f new_name=staging" \
  "gh api -X PUT repos/$org/x/branches/feat/y/protection --input p.json" \
  'gh api -X PATCH http://api.github.com/repos/o/r -f private=false' \
  'gh api -X PATCH https://api.github.com:443/repos/o/r -f private=false' \
  'gh api -X PATCH //repos/o/r -f private=false' \
  'gh api -X PATCH repos//o/r -f private=false' \
  'gh api -X PUT teams/123/repos/o/r -f permission=admin'; do
  g bloquea "$c" '(repos)'
done
for c in \
  "\"C:\\Program Files\\GitHub CLI\\gh.exe\" repo create $org/x --private --team $equipo" \
  "gh repo deploy-key -R $org/x list" \
  "gh repo deploy-key delete 123 -R $org/x" \
  "gh repo create $org/app \\
  --private --team $equipo" \
  'gh api -X PATCH repos/{owner}/{repo}/pulls/5 \
  -f title=x' \
  "gh api graphql -f query='query(\$o:String!){organization(login:\$o){id}}' -f o=x" \
  "gh api repos/$org/x/branches/feat/y/protection" \
  'gh api repos/{owner}/{repo}/issues/5/comments -F body=@comentario.md'; do
  g permite "$c"
done
g bloquea 'git.exe push origin HEAD:staging' '(staging)'
g bloquea '/usr/bin/git push origin HEAD:staging' '(staging)'
g bloquea 'gh api repos/{owner}/{repo}/issues/5/comments -f body="usa gh api -X PATCH"' 'body=@'

echo "== SessionStart: repos públicos en $org y en $bot (A2, C1)"
# gh falso para check-public-repos.sh. Solo responde la consulta exacta del hook (un cambio de flags
# rompe la suite); la respuesta sale de FAKE_PUB_ORG y FAKE_PUB_BOT: vacio, falla, lento, noinstalado
# (127), mil (1000 repos), crlf:<lista> o una lista de repos separada por comas.
mkdir -p "$tmp/gh-publicos"
cat > "$tmp/gh-publicos/gh" <<'GH'
#!/usr/bin/env bash
[ "$*" = "repo list ${3:-} --visibility public --limit 1000 --json nameWithOwner --jq .[].nameWithOwner" ] ||
  { echo "consulta inesperada: $*" >&2; exit 1; }
case "$3" in
  "$FAKE_ORG") r=${FAKE_PUB_ORG:-vacio} ;;
  "$FAKE_BOT") r=${FAKE_PUB_BOT:-vacio} ;;
  *) exit 1 ;;
esac
case "$r" in
  vacio) exit 0 ;;
  falla) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
  lento) sleep 5; exit 0 ;;
  noinstalado) exit 127 ;;
  mil) for i in $(seq 1 1000); do printf '%s/r%s\n' "$3" "$i"; done ;;
  crlf:*) r=${r#crlf:}; printf '%s\r\n' ${r//,/ } ;;
  *) printf '%s\n' ${r//,/ } ;;
esac
GH
chmod +x "$tmp/gh-publicos/gh"
# sesion <texto requerido> <texto prohibido o -> <descripción> [VAR=valor ...]: corre
# check-public-repos.sh (de hooks_alt o de la copia base) con el gh falso. Exige salida 0, el texto
# requerido en stdout y que no aparezca el prohibido.
sesion() {
  local quiere=$1 prohibido=$2 desc=$3 out salio
  shift 3
  out=$(env FAKE_ORG="$org" FAKE_BOT="$bot" "$@" PATH="$tmp/gh-publicos:$PATH" \
    bash "${hooks_alt:-$hooks}/check-public-repos.sh" </dev/null 2>/dev/null)
  salio=$?
  if [ "$salio" -eq 0 ] && [[ "$out" == *"$quiere"* ]] && { [ "$prohibido" = - ] || [[ "$out" != *"$prohibido"* ]]; }; then
    ok=$((ok + 1))
    printf 'ok     sesion   %s\n' "$desc"
  else
    fallos=$((fallos + 1))
    printf 'FALLO  sesion   %s (salió %s; stdout: "%s")\n' "$desc" "$salio" "${out//$'\n'/ | }"
  fi
}
sesion 'Repos públicos: OK' 'ALERTA' 'ninguna cuenta tiene repos públicos'
sesion "- $org/web" 'Repos públicos: OK' "ALERTA con los repos públicos de $org" FAKE_PUB_ORG="$org/api,$org/web"
sesion 'Repos públicos: ALERTA. Avísale a Leonardo' 'Repos públicos: OK' "ALERTA en $org, con la instrucción en la misma línea" FAKE_PUB_ORG="$org/api"
sesion "- $bot/copia" 'Repos públicos: OK' "ALERTA con los repos públicos de $bot" FAKE_PUB_BOT="$bot/copia"
sesion 'NO SE PUDO VERIFICAR' 'Repos públicos: OK' "gh falla en $org" FAKE_PUB_ORG=falla
sesion "$org: gh: HTTP 502" 'Repos públicos: OK' "gh falla en $org: la nombra con la causa" FAKE_PUB_ORG=falla
sesion 'NO SE PUDO VERIFICAR' 'Repos públicos: OK' "gh falla en $bot" FAKE_PUB_BOT=falla
sesion "$bot: gh: HTTP 502" 'Repos públicos: OK' "gh falla en $bot: la nombra con la causa" FAKE_PUB_BOT=falla
sesion 'Repos públicos: ALERTA' 'Repos públicos: OK' "ALERTA en $org aunque $bot falle" FAKE_PUB_ORG="$org/api" FAKE_PUB_BOT=falla
sesion "Además, no se pudo verificar: $bot" - "ALERTA en $org y aviso de que $bot falló" FAKE_PUB_ORG="$org/api" FAKE_PUB_BOT=falla
sesion "Además, no se pudo verificar: $org" - "ALERTA en $bot y aviso de que $org falló" FAKE_PUB_BOT="$bot/copia" FAKE_PUB_ORG=falla
sesion 'NO SE PUDO VERIFICAR' 'Repos públicos: OK' 'gh tarda más que el límite' FAKE_PUB_ORG=lento REPOS_PUBLICOS_TIMEOUT=1
sesion 'límite de 1 s' 'Repos públicos: OK' 'gh tarda más que el límite: lo dice' FAKE_PUB_ORG=lento REPOS_PUBLICOS_TIMEOUT=1
sesion 'no está instalado' 'Repos públicos: OK' 'gh no instalado' FAKE_PUB_ORG=noinstalado
sesion 'Repos públicos: OK' 'ALERTA' 'REPOS_PUBLICOS_TIMEOUT inválido usa el valor por defecto' REPOS_PUBLICOS_TIMEOUT=abc
sesion "- $org/web" $'\r' 'salida de gh con CRLF: los repos salen sin \r' FAKE_PUB_ORG="crlf:$org/api,$org/web"
sesion 'y 950 más' 'Repos públicos: OK' 'lista larga: muestra 50 y cuenta el resto' FAKE_PUB_ORG=mil
sesion 'posiblemente incompleta' 'Repos públicos: OK' 'una cuenta con 1000 repos públicos: avisa que la lista puede estar incompleta' FAKE_PUB_ORG=mil
mkdir -p "$tmp/reglas/sesion-sin-org/.claude/hooks" "$tmp/reglas/sesion-sin-bot/.claude/hooks"
cp "$hooks/check-public-repos.sh" "$tmp/reglas/sesion-sin-org/.claude/hooks/" 2>/dev/null
cp "$hooks/check-public-repos.sh" "$tmp/reglas/sesion-sin-bot/.claude/hooks/" 2>/dev/null
printf 'dueno=%s\nbot=%s\nequipo=%s\n' "$dueno" "$bot" "$equipo" > "$tmp/reglas/sesion-sin-org/.claude/pipeline.conf"
printf 'dueno=%s\norg=%s\nequipo=%s\n' "$dueno" "$org" "$equipo" > "$tmp/reglas/sesion-sin-bot/.claude/pipeline.conf"
hooks_alt="$tmp/reglas/sesion-sin-org/.claude/hooks"
sesion 'NO SE PUDO VERIFICAR' 'Repos públicos: OK' 'pipeline.conf sin org'
hooks_alt="$tmp/reglas/sesion-sin-bot/.claude/hooks"
sesion 'NO SE PUDO VERIFICAR' 'Repos públicos: OK' 'pipeline.conf sin bot'
hooks_alt=""

echo "== /crear-repo (A2, C3)"
cr="$repo/.claude/commands/crear-repo.md"
chequeo pasa 'existe .claude/commands/crear-repo.md' test -f "$cr"
tiene() { tr -d '\r' < "$cr" 2>/dev/null | grep -qF -- "$1"; }
for t in 'gh repo create <org>/<nombre> --private --team <equipo> --add-readme' 'rules/branches/main' \
  'rules/branches/staging' 'git clone https://github.com/<org>/<nombre>.git <ruta>' 'feat/T0-framework' \
  '--base main' 'git -C <ruta> push origin origin/main:refs/heads/staging' 'ESPERANDO OK' 'HUMAN' \
  'Solo en una sesión interactiva' 'test -f instalador/instalar.sh' 'crear .claude/identidad-agente.txt' \
  'rama staging: crear' '<scratchpad>' 'nunca con `mktemp`' 'docs/adr/0001-' '.pipeline/modo' \
  'no corras las secciones 1 y 2' 'git -C <scratchpad>/sim-<nombre> remote add origin https://github.com/<org>/<nombre>.git' \
  "-d '<descripción>'" 'un vencimiento del timeout no es un fallo'; do
  chequeo pasa "crear-repo.md: $t" tiene "$t"
done
# El paso 0 de /crear-repo reconoce el instalador nuevo (B) por su salida. Con el instalador de este
# repo, sobre una simulación con origin de la organización y un commit, tiene que cortar. B invierte
# este chequeo. Solo en el repo del framework, que tiene instalador/.
if [ -f "$repo/instalador/instalar.sh" ]; then
  sim="$tmp/sim-app"
  git init -q "$sim" 2>/dev/null
  git -C "$sim" remote add origin "https://github.com/$org/app.git"
  git -C "$sim" -c user.name=prueba -c user.email=prueba@example.com commit -q --allow-empty -m sim
  salida_sim=$(bash "$repo/instalador/instalar.sh" "$sim" 2>&1)
  paso0_pasa() {
    printf '%s\n' "$salida_sim" | grep -qx 'crear .claude/identidad-agente.txt' &&
      ! printf '%s\n' "$salida_sim" | grep -qx 'rama staging: crear' &&
      ! printf '%s\n' "$salida_sim" | grep -q '^nota:'
  }
  chequeo falla 'el paso 0 de /crear-repo corta con el instalador actual (v1, antes de B)' paso0_pasa
else
  echo "omitido: no hay instalador/ (repo instalado), paso 0 de /crear-repo"
fi
# Los comandos de los bloques de código pasan el hook, con los marcadores reemplazados.
mkdir -p "$tmp/scratch"
cp "$tmp/con-codeowners/.github/CODEOWNERS" "$tmp/cuerpo.md" 2>/dev/null
comandos_cr=$(tr -d '\r' < "$cr" 2>/dev/null |
  awk '/^ *```/ { dentro = !dentro; next } dentro && /^ *(gh|git|bash) / { sub(/^ +/, ""); print }' |
  sed -e "s#<org>#$org#g; s#<equipo>#$equipo#g; s#<nombre>#app#g; s#<ruta>#$tmp/con-codeowners#g" \
      -e "s#<n>#5#g; s#<archivo>#$tmp/cuerpo.md#g; s#<descripción>#API de prueba#g" \
      -e "s#<scratchpad>#$tmp/scratch#g; s#<titulo>#prueba#g")
chequeo falla 'los comandos de crear-repo.md no dejan marcadores sin reemplazar' grep -q '<[a-zA-Z][^ >]*>' <<< "$comandos_cr"
chequeo pasa 'crear-repo.md trae comandos en bloques de código' test -n "$comandos_cr"
while IFS= read -r c; do
  [ -n "$c" ] && g permite "$c"
done <<< "$comandos_cr"

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
# el dueño del conf (@$dueno).
codeowners_patrones() {
  local l p d resto
  while IFS= read -r l || [ -n "$l" ]; do
    l=$(recortar "$l")
    case "$l" in ''|'#'*) continue ;; esac
    read -r p d resto <<< "$l"
    { [ "$d" = "@$dueno" ] && [ -z "$resto" ]; } || return 1
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
# El dueño sale de pipeline.conf (T3a): con otro dueño en el conf, el CODEOWNERS del repo no coincide.
con_otro_dueno() { local dueno=otro-dueno; comparar_codeowners "$@"; }
chequeo falla 'con otro dueño en pipeline.conf, el CODEOWNERS del repo no coincide' con_otro_dueno "$reglas" "$co"
grep -v 'CLAUDE.md' "$co" > "$v/falta" 2>/dev/null
chequeo falla 'CODEOWNERS al que le falta una regla' comparar_codeowners "$reglas" "$v/falta"
{ cat "$co" 2>/dev/null; echo "/docs/ @$dueno"; } > "$v/sobra"
chequeo falla 'CODEOWNERS con una regla de más' comparar_codeowners "$reglas" "$v/sobra"
sed "s/@$dueno/@otro/" "$co" > "$v/otro" 2>/dev/null
chequeo falla 'CODEOWNERS con otro dueño' comparar_codeowners "$reglas" "$v/otro"
sed "s/@$dueno/@$dueno @otro/" "$co" > "$v/dos" 2>/dev/null
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
# Railway (T3a): la sesión de Leonardo y el MCP de Railway quedan fuera del alcance del agente.
for regla in 'Read(~/.railway/**)' 'Edit(~/.railway/**)' 'Write(~/.railway/**)' 'mcp__railway'; do
  chequeo pasa "settings.json deniega $regla" deniega "$regla"
done
permite_regla() { jq -e --arg r "$1" '.permissions.allow | index($r) != null' "$s"; }
chequeo falla 'settings.json ya no aprueba solo Bash(railway environment*)' permite_regla 'Bash(railway environment*)'
tiene_linea() { tr -d '\r' < "$2" | grep -qxF "$1"; }
chequeo pasa '.gitignore ignora .claude/settings.local.json' tiene_linea '.claude/settings.local.json' "$repo/.gitignore"
chequeo pasa '.gitignore ignora .claude/worktrees/ (worktrees del engineer)' tiene_linea '.claude/worktrees/' "$repo/.gitignore"
# pipeline.conf (T3a): define el dueño, el bot y el email del bot que usa la suite.
chequeo pasa 'pipeline.conf define dueno' test -n "$dueno"
chequeo pasa 'pipeline.conf define bot' test -n "$bot"
chequeo pasa 'pipeline.conf define bot_email' test -n "$bot_email"
chequeo pasa 'el email del bot es el noreply del bot' test "${bot_email#*+}" = "$bot@users.noreply.github.com"
# pipeline.conf (A1): la organización donde el agente crea repos y el equipo obligatorio.
chequeo pasa 'pipeline.conf define org' test -n "$org"
chequeo pasa 'pipeline.conf define equipo' test -n "$equipo"
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
  chequeo pasa "la plantilla fija el autor $bot" campo GIT_AUTHOR_NAME "$bot"
  chequeo pasa "la plantilla fija el committer $bot" campo GIT_COMMITTER_NAME "$bot"
  chequeo pasa 'la plantilla usa el email noreply del autor' campo GIT_AUTHOR_EMAIL "$bot_email"
  chequeo pasa 'la plantilla usa el email noreply del committer' campo GIT_COMMITTER_EMAIL "$bot_email"
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
# Job secrets sin licencia (A2, C4): gitleaks (MIT) en binario con SHA-256 fijo, sin gitleaks-action,
# que pide licencia en repos de organización. El nombre del job es el check de los rulesets.
job_secrets() { bloque_yaml "$ci" secrets '  '; }
chequeo pasa 'el job secrets existe con ese nombre (check de los rulesets)' en_bloque job_secrets '^    runs-on: ubuntu-latest$'
chequeo falla 'ci.yml no usa gitleaks-action' grep -q 'gitleaks/gitleaks-action' "$ci"
chequeo pasa 'secrets fija gitleaks 8.30.1' en_bloque job_secrets 'v=8\.30\.1$'
chequeo pasa 'secrets fija el SHA-256 del binario linux_x64' en_bloque job_secrets '551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb'
chequeo pasa 'secrets comprueba el SHA-256 con sha256sum -c' en_bloque job_secrets 'sha256sum -c -'
chequeo pasa 'secrets baja de la release oficial de gitleaks' en_bloque job_secrets 'https://github\.com/gitleaks/gitleaks/releases/download/'
chequeo pasa 'secrets escanea todo el historial (fetch-depth: 0 y gitleaks git)' en_bloque job_secrets 'fetch-depth: 0'
chequeo pasa 'secrets corre gitleaks git' en_bloque job_secrets '\./gitleaks git '
chequeo pasa 'secrets declara permissions: contents: read' en_bloque job_secrets '^      contents: read$'
chequeo pasa 'secrets no acepta comentarios gitleaks:allow' en_bloque job_secrets ' --ignore-gitleaks-allow'
chequeo pasa 'secrets escanea también el contenido de los merges (-m)' en_bloque job_secrets ' --log-opts="--all --full-history -m"'
chequeo pasa 'secrets falla si gitleaks escribe ERR o no escanea commits' en_bloque job_secrets "' ERR \|INF 0 commits scanned'"
# .gitleaksignore y .gitleaks.toml apagan hallazgos: son rutas de gobierno (A2).
for r in .gitleaksignore .gitleaks.toml; do
  chequeo pasa "rutas-gobierno.txt incluye $r" tiene_linea "$r" "$repo/.claude/rutas-gobierno.txt"
done
# Modelos (A2, C5), verificados contra Claude Code 2.1.285.
chequeo pasa 'settings.json: modelo del CTO claude-opus-5-5' jq -e '.model == "claude-opus-5-5"' "$s"
chequeo pasa 'settings.json: effortLevel xhigh' jq -e '.effortLevel == "xhigh"' "$s"
chequeo pasa 'settings.json: sin la clave ultracode' jq -e 'has("ultracode") | not' "$s"
# fm <archivo> <clave>: valor de una clave de primer nivel del frontmatter de un agente.
fm() {
  tr -d '\r' < "$1" | awk -v k="$2" '
    NR == 1 && /^---/ { f = 1; next }
    f && /^---/ { exit }
    f && index($0, k ": ") == 1 { print substr($0, length(k) + 3); exit }'
}
ag="$repo/.claude/agents"
chequeo pasa 'engineer.md: model claude-sonnet-5-5' test "$(fm "$ag/engineer.md" model)" = claude-sonnet-5-5
chequeo pasa 'engineer.md: effort xhigh (nunca max)' test "$(fm "$ag/engineer.md" effort)" = xhigh
chequeo pasa 'test-writer.md: model sonnet' test "$(fm "$ag/test-writer.md" model)" = sonnet
chequeo pasa 'test-writer.md: effort high' test "$(fm "$ag/test-writer.md" effort)" = high
chequeo pasa 'auditor.md: model claude-opus-5-5' test "$(fm "$ag/auditor.md" model)" = claude-opus-5-5
chequeo pasa 'auditor.md: effort high' test "$(fm "$ag/auditor.md" effort)" = high
chequeo falla 'ningún agente usa Fable (ni el alias best, que hoy resuelve a Fable)' grep -Eqi '^model: *(best|[^ ]*fable)' "$ag"/*.md
# SessionStart (A2, C1): check-public-repos.sh, sin matcher y con timeout.
chequeo pasa 'settings.json registra check-public-repos.sh en SessionStart' \
  jq -e '[.hooks.SessionStart[]?.hooks[]? | select(.type == "command" and (.command | test("check-public-repos\\.sh")))] | length == 1' "$s"
chequeo pasa 'SessionStart sin matcher (todas las fuentes)' jq -e '[.hooks.SessionStart[]? | select(has("matcher"))] | length == 0' "$s"
chequeo pasa 'SessionStart con timeout de 50 s o más (dos consultas de 20 s y margen)' \
  jq -e '[.hooks.SessionStart[]?.hooks[]? | select(.command | test("check-public-repos")) | .timeout | numbers | select(. >= 50)] | length == 1' "$s"

echo "== protocolo: lecciones, proceso ligero y auditores (lecciones, T2)"
tiene_texto() { tr -d '\r' < "$2" | grep -qF -- "$1"; }
cl="$repo/CLAUDE.md"
au="$repo/.claude/agents/auditor.md"
ac="$repo/.claude/prompts/auditor-codex.md"
chequeo pasa 'existe .pipeline/lecciones-pendientes.md' test -f "$repo/.pipeline/lecciones-pendientes.md"
chequeo falla '.pipeline/ no es ruta de gobierno' grep -Eq '^(\*\*/)?\.pipeline' "$repo/.claude/rutas-gobierno.txt"
chequeo pasa 'CLAUDE.md: el new_lesson va a lecciones pendientes' tiene_texto 'agrégala a `.pipeline/lecciones-pendientes.md`' "$cl"
chequeo pasa 'CLAUDE.md: un PR de lecciones al cierre del proyecto o con 5 pendientes' tiene_texto 'cuando haya 5 lecciones pendientes' "$cl"
chequeo pasa 'CLAUDE.md: el engineer nunca recibe las pendientes (Fase 3, paso 3)' tiene_texto 'solo `LESSONS.md`, nunca las pendientes' "$cl"
chequeo pasa 'CLAUDE.md: el engineer nunca recibe las pendientes (tabla de roles)' tiene_texto 'LESSONS.md (nunca las lecciones pendientes)' "$cl"
chequeo pasa 'CLAUDE.md: el engineer nunca recibe las pendientes (Memoria del sistema)' tiene_texto 'el engineer nunca recibe las pendientes' "$cl"
chequeo pasa 'CLAUDE.md: el new_lesson de Codex también va a pendientes' tiene_texto 'Si Codex trae `new_lesson`, también va a `.pipeline/lecciones-pendientes.md`' "$cl"
chequeo pasa 'CLAUDE.md: el router dice que el proceso ligero no ejecuta JEV' tiene_texto 'En el proceso ligero no se ejecuta JEV' "$cl"
# SETUP.md es la guía de este repo; el instalador no la copia a los repos instalados (T3b, C2).
if [ -f "$repo/SETUP.md" ]; then
  chequeo pasa 'SETUP.md: el remedio del paso c dice que el hook bloquea git credential-manager' tiene_texto 'y `git credential-manager`, salvo `github list`' "$repo/SETUP.md"
else
  echo "omitido: no hay SETUP.md (repo instalado)"
fi
chequeo pasa 'CLAUDE.md: proceso ligero para PRs que solo tocan rutas de gobierno' tiene_texto 'una ronda del auditor Claude y la aprobación de Leonardo como code owner' "$cl"
chequeo pasa 'CLAUDE.md: el proceso ligero exige code owners activo en staging y main' tiene_texto 'protección con code owners esté activa en `staging` y `main`' "$cl"
chequeo pasa 'auditor.md: evasiones fuera del modelo de amenaza con severidad baja' tiene_texto 'las evasiones que quedan fuera de él se reportan con severidad baja' "$au"
chequeo pasa 'auditor-codex.md: evasiones fuera del modelo de amenaza con severidad baja' tiene_texto 'las evasiones que quedan fuera de él se reportan con severidad baja' "$ac"
chequeo pasa 'auditor.md: el new_lesson va a lecciones pendientes' tiene_texto '.pipeline/lecciones-pendientes.md' "$au"
# Repos instalados (instalable): el hook Stop del engineer tiene tiempo para npm test en Windows.
# Solo dentro del frontmatter y con la misma sangría que el command: de run-tests.sh (la clave
# timeout de ese hook); un timeout en otro nivel lo ignora Claude Code.
stop_timeout() {
  tr -d '\r' < "$repo/.claude/agents/engineer.md" | awk '
    NR == 1 && /^---/ { fm = 1; next }
    fm && /^---/ { exit }
    fm && /command:.*run-tests\.sh/ { match($0, /^ */); ind = RLENGTH; f = 1; next }
    fm && f && /^ *timeout:/ { match($0, /^ */); if (RLENGTH == ind) print; exit }' | grep -Eq 'timeout: *600$'
}
chequeo pasa 'engineer.md: el hook Stop declara timeout: 600' stop_timeout
# Flujo del engineer en worktrees (T3a).
chequeo pasa 'engineer.md: en su worktree hace git switch a la rama de la subtarea' tiene_texto 'git switch <rama>' "$repo/.claude/agents/engineer.md"
chequeo pasa 'CLAUDE.md: el CTO no deja activa la rama de la subtarea en su checkout' tiene_texto 'no la dejes activa en tu checkout' "$cl"
# Repos en la organización (A2, C2 y C6).
for t in 'solo con `/crear-repo <nombre>`, después del sí de la Fase 1' 'Repos públicos:' \
  '`ALERTA`: avísale a Leonardo en la primera línea de tu respuesta' 'detente y espera su instrucción' \
  'un error no equivale a cero repos públicos' 'el aviso de `ALERTA` termina con la línea `ESPERANDO OK`' \
  'rules/branches/<rama>` debe traer' 'los `gh repo` que escriben' 'gh api -F body=@archivo'; do
  chequeo pasa "CLAUDE.md: $t" tiene_texto "$t" "$cl"
done
# Modelos en la tabla de roles (A2, C5).
for t in '`claude-sonnet-5-5`), esfuerzo muy alto (`effort: xhigh`), nunca `max`' '`"effortLevel": "xhigh"`' \
  'Ningún rol usa Fable' 'se revisa con los datos de las primeras 3 a 5 tareas reales' \
  'Si el engineer en Sonnet necesita más intentos, vuelve a Opus'; do
  chequeo pasa "CLAUDE.md: $t" tiene_texto "$t" "$cl"
done
chequeo falla 'CLAUDE.md ya no fija "ultracode": true' tiene_texto '"ultracode": true' "$cl"
# Después de la verificación y revisión previa al auditor (A2): alcance de la regla de sesión, la
# verificación manual fallida, el PR T0 en todas las compuertas y el texto para repos instalados.
for t in 'los subagentes ignoran esta regla' 'no corras `/crear-repo` hasta que la verificación dé `OK`' \
  'ESPERANDO OK: repos públicos' 'es la única vez que `staging` nace por push' 'reemplaza el `protected: true`' \
  'En el repo del framework' 'el ADR, el modo y las variables van en el repo nuevo' 'nunca con `mktemp`'; do
  chequeo pasa "CLAUDE.md: $t" tiene_texto "$t" "$cl"
done
chequeo falla 'CLAUDE.md ya no dice que rules/branches reemplaza el GET de Leonardo' tiene_texto 'reemplaza el GET de Leonardo' "$cl"
chequeo falla 'CLAUDE.md ya no dice "En este repo es colaboradora"' tiene_texto 'En este repo es colaboradora' "$cl"
chequeo pasa 'CLAUDE.md: el PR T0 también es excepción en Cambios en rutas de gobierno y en el proceso ligero' \
  tiene_texto 'salvo el PR T0 (ver Repos en la organización)' "$cl"
cuenta_t0() { [ "$(tr -d '\r' < "$cl" | grep -c 'PR T0')" -ge 4 ]; }
chequeo pasa 'CLAUDE.md cita el PR T0 en Repos en la organización, Fase 0, Fase 3 y Fase 4' cuenta_t0
# SETUP.md, organización (A2, C7). Solo en este repo: el instalador no copia SETUP.md.
if [ -f "$repo/SETUP.md" ]; then
  for t in "gh api -X POST orgs/$org/rulesets" '"do_not_enforce_on_create": true' '"bypass_actors": []' \
    'members_can_create_pages' 'Stop usage' 'All repositories' "$org/prueba-rulesets" \
    "fine-grained con dueño \`$org\`" 'sha256sum -c' 'GH013' '24221749' '24221758' '`.gitleaks.toml`' \
    'audit log'; do
    chequeo pasa "SETUP.md: $t" tiene_texto "$t" "$repo/SETUP.md"
  done
  chequeo falla 'SETUP.md ya no sugiere quitar el job secrets' tiene_texto 'quita el job `secrets`' "$repo/SETUP.md"
else
  echo "omitido: no hay SETUP.md (repo instalado), chequeos de la organización"
fi

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
# El engineer corre en un worktree aislado (isolation: worktree), en <repo>/.claude/worktrees/<n>/:
# la ruta se mide desde la raíz del worktree (T3a).
p permite 'C:\Users\dev\repo\.claude\worktrees\agent-a1\src\app.py'
p permite 'C:\Users\dev\repo\.claude\worktrees\agent-a1\tests\unit\test_app.py'
p permite '/home/dev/repo/.claude/worktrees/agent-a1/src/app.py'
p permite '/home/dev/repo/.claude/worktrees/agent-a1/instalador/instalar.sh'
p bloquea 'C:\Users\dev\repo\.claude\worktrees\agent-a1\tests\acceptance\test_c1.py'
p bloquea 'C:\Users\dev\repo\.claude\worktrees\agent-a1\.claude\hooks\guard-commands.sh'
p bloquea 'C:\Users\dev\repo\.claude\worktrees\agent-a1\.claude\settings.json'
p bloquea 'C:\Users\dev\repo\.claude\worktrees\agent-a1\CLAUDE.md'
p bloquea 'C:\Users\dev\repo\.claude\worktrees\agent-a1\LESSONS.md'
p bloquea 'C:\Users\dev\repo\.claude\worktrees\agent-a1\docs\adr\0001-stack.md'
p bloquea 'C:\Users\dev\repo\.claude\worktrees\agent-a1\.github\workflows\ci.yml'
p bloquea '/home/dev/repo/.claude/worktrees/agent-a1/../../hooks/guard-commands.sh'
p bloquea '/home/dev/repo/.claude/worktrees/agent-a1/src/../../../settings.json'
p bloquea '/home/dev/repo/.claude/worktrees/'
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
