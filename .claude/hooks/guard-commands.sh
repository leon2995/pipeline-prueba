#!/usr/bin/env bash
# Bloquea comandos peligrosos en cualquier agente. Recibe el JSON del hook por stdin.
# Salida 2 = bloquear y devolver el mensaje de stderr al agente.
#
# Modelo de amenaza: errores de un agente, no ofuscación deliberada. El hook bloquea el push
# forzado y el borrado de ramas escritos de forma directa o con sintaxis de shell común. El
# control efectivo sobre main y staging es la protección de ramas de GitHub
# (allow_force_pushes y allow_deletions en false, enforce_admins en true). Las ramas de
# trabajo (feat/*, fix/*) no tienen esa protección: ahí el hook es la única barrera.
#
# Auditorías de hook-force-push. Ronda 1: sus evasiones están cerradas y tienen caso en
# scripts/test-hooks.sh (--for"ce", git >/dev/null push -f, --m, git branch '-d', \r final,
# awk roto que sale con 1). Ronda 2 y límites declarados: el hook las deja pasar y no se
# persiguen, porque imitar la gramática de bash con awk nunca queda completo; cada ronda de
# auditoría encontró otra construcción.
# - Separador dentro de comillas o escapado: git push origin "a&b" -f, git push
#   "https://host/repo.git?a=1&b=2" -f, git push origin "a;b" -d rama, git push origin a\&b -f.
# - Redirección pegada a git: git>/dev/null push -f, git>/dev/null branch -d rama.
# - Continuación de línea dentro de un flag: git push -\<salto de línea>f, git branch -\<salto>d.
# - Expansión de llaves: git push -{u,f}, git branch -{r,d} origin/rama.
# - Config indirecta: FORCE=+HEAD:refs/heads/x git --config-env=remote.origin.push=FORCE push,
#   y la forma separada git --config-env remote.origin.push=FORCE push.
# - Flag en variable (V=--force; git push origin x $V), en sustitución de comandos
#   (git push origin x $(printf '\x2df')) o en escape hexadecimal (git push origin $'\x2df' x).
# - Config persistente y aliases: git config remote.origin.push +refs/heads/*:refs/heads/*,
#   git config alias.pf "push --force".
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
input=$(cat)
cmd=$(printf '%s' "$input" | json_get command)
[ -z "$cmd" ] && exit 0

# Analiza las invocaciones de git y responde una sola palabra: force, main, borrado o limpio.
# - force: push forzado en cualquier forma y posición. --force, --force-with-lease,
#   --force-if-includes y sus abreviaturas desde --f; -f solo o combinado (-uf, -fu); --mirror y
#   sus abreviaturas desde --m (fuerza updates); refspecs con + (git push origin +rama);
#   -c remote.<r>.push=+... o mirror=, y lo mismo por GIT_CONFIG_* antes de git.
# - main: push a main (git push origin main, HEAD:main, refs/heads/main). Lo mergea Leonardo.
# - borrado: borrar ramas siempre requiere OK de Leonardo. git branch con -d (borrado "seguro")
#   se bloquea igual que -D a propósito, junto con combinados (-rd, -rD) y --delete y sus
#   abreviaturas; también las ramas remotas (git push --delete, -d o :rama) y git update-ref -d.
#   No lo relajes sin un PR aprobado por él.
# Cómo lee el comando: quita redirecciones (2>&1, &>, >|, > archivo), parte por ; & | y saltos
# de línea, y en cada palabra quita comillas, \, $, (, ), { y } en cualquier posición, porque
# bash convierte --for"ce" y p\ush en --force y push. No respeta comillas al partir, a propósito,
# para ver dentro de bash -c "git push -f". Costo aceptado: un git commit -m que diga
# literalmente "git push --force" se bloquea; usa git commit -F archivo.
# Es una barrera contra errores, no contra ofuscación: no ve aliases de git, config persistente
# (git config remote.<r>.push +...) ni flags escondidos en variables o sustitución de comandos
# (V=--force; git push origin x $V).
analizar_git() {
  printf '%s\n' "$1" | awk '
    function prefijo(t, opcion) { return length(t) >= 3 && index(opcion, t) == 1 }
    function limpiar(t) { t = tolower(t); gsub(/["\047`\\$(){}]/, "", t); return t }
    function marcar(r) { if (r == "force" || res == "limpio") res = r }
    BEGIN { RS = "\001"; res = "limpio" }
    {
      s = $0
      gsub(/\\\r?\n/, " ", s)                 # continuación de línea
      gsub(/[0-9]*[<>]&[0-9]*-?/, " ", s)     # 2>&1, >&2, 1>&-
      gsub(/&>>?|>\|/, " > ", s)              # &>, &>>, >|
      nseg = split(s, segs, /[;&|\n]/)
      for (k = 1; k <= nseg; k++) {
        ntok = split(segs[k], tok, /[ \t\r]+/)
        estado = 0   # 0: busca git, 1: opciones globales, 2: args de push, 3: args de branch/update-ref
        for (i = 1; i <= ntok; i++) {
          if (tok[i] ~ /^[0-9]*[<>]/) {         # redirección: >archivo, 2>err, < archivo, <<EOF
            if (tok[i] ~ /^[0-9]*[<>]+$/) i++
            continue
          }
          t = limpiar(tok[i])
          if (t == "") continue
          if (estado == 0) {
            if (t ~ /^git_config/ && t ~ /push=\+|mirror|=\+/) marcar("force")
            con_barras = tolower(tok[i]); gsub(/["\047`]/, "", con_barras)
            if (t ~ /(^|\/)git(\.exe)?$/ || con_barras ~ /\\git(\.exe)?$/) estado = 1
          } else if (estado == 1) {
            if (t ~ /^(-c|--git-dir|--work-tree|--namespace|--config-env|--attr-source|--super-prefix)$/) {
              i++
              if (limpiar(tok[i]) ~ /push=\+|mirror=/) marcar("force")
            } else if (t !~ /^-/) {
              estado = (t == "push") ? 2 : (t == "branch" || t == "update-ref") ? 3 : 0
            }
          } else if (estado == 2) {
            op = t; sub(/=.*/, "", op)
            if (op ~ /^--force/ || prefijo(op, "--force-with-lease") || prefijo(op, "--force-if-includes") || prefijo(op, "--mirror") || t ~ /^-[a-z0-9]*f[a-z0-9]*$/ || t ~ /^\+./)
              marcar("force")
            else if (t == "main" || t ~ /:(refs\/heads\/)?main$/)
              marcar("main")
            else if (t ~ /^-[a-z0-9]*d[a-z0-9]*$/ || prefijo(op, "--delete") || t ~ /^:./)
              marcar("borrado")
          } else if (t ~ /^-[a-z]*d[a-z]*$/ || prefijo(t, "--delete")) {
            marcar("borrado")
          }
        }
      }
    }
    END { print res }'
}
msg_borrado="Bloqueado por protocolo (borrar ramas: git branch -d/-D/--delete, git push --delete o :rama, git update-ref -d, gh pr merge -d/--delete-branch). Si de verdad hace falta, pídele a Leonardo que lo ejecute él."
veredicto=$(analizar_git "$cmd")
veredicto=${veredicto%$'\r'}
case "$veredicto" in
  limpio) ;;
  force)
    echo "Bloqueado por protocolo (push forzado: --force, --force-with-lease, -f, --mirror o refspec con +). Si de verdad hace falta, pídele a Leonardo que lo ejecute él." >&2
    exit 2 ;;
  main)
    echo "Bloqueado por protocolo (push a main). El merge a main lo hace Leonardo." >&2
    exit 2 ;;
  borrado)
    echo "$msg_borrado" >&2
    exit 2 ;;
  *)
    # Fail-closed acotado: si awk no responde una palabra válida (no existe, se cae, sale con
    # cualquier código sin imprimir) no sabemos qué hace el comando. Se bloquea lo que mencione
    # push o branch; el resto sigue funcionando para poder diagnosticar.
    if printf '%s' "$cmd" | grep -Eqi 'push|branch'; then
      echo "Bloqueado por protocolo: no pude analizar el comando (awk respondió '${veredicto}'). Revisa que awk funcione." >&2
      exit 2
    fi ;;
esac

deny_patterns=(
  'git reset --hard'
  'git clean -f'
  'rm -rf'
  'railway up'
  'railway redeploy'
  'railway variables (set|delete)'
  'railway (delete|down)'
  'railway environment delete'
  'railway service delete'
  'DROP (TABLE|DATABASE|SCHEMA)'
  'TRUNCATE'
  'cat .*\.env'
  'printenv'
  '^env( |$)'
  'echo \$[A-Za-z_]*(TOKEN|KEY|SECRET|PASSWORD)'
  'curl .* (-d|--data|-X POST|-X PUT|-X DELETE)'
)
for p in "${deny_patterns[@]}"; do
  if printf '%s' "$cmd" | grep -Eiq "$p"; then
    echo "Bloqueado por protocolo (patrón: $p). Si de verdad hace falta, pídele a Leonardo que lo ejecute él." >&2
    exit 2
  fi
done

# railway variables: solo nombres, nunca valores
if printf '%s' "$cmd" | grep -Eq '^railway variables' && ! printf '%s' "$cmd" | grep -Eq "cut -d= -f1|jq (-r )?'keys'"; then
  echo "Bloqueado: 'railway variables' solo se permite listando nombres, por ejemplo: railway variables --kv | cut -d= -f1" >&2
  exit 2
fi
# gh pr merge: solo a staging, un merge por comando, sin --admin, --auto ni borrar la rama, y
# nunca un PR que toque (modifique, borre o renombre) una ruta de .claude/rutas-gobierno.txt:
# esos los mergea Leonardo, también a staging. Si algo no se puede verificar, se bloquea.
if printf '%s' "$cmd" | grep -Eq '(^|[;&| ])gh pr merge'; then
  bloquear() { echo "Bloqueado por protocolo: $1" >&2; exit 2; }
  minusculas() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

  merges=$(printf '%s\n' "$cmd" | grep -Eo '(^|[;&| ])gh pr merge' | wc -l)
  [ $((merges)) -gt 1 ] && bloquear "un merge por comando. Corre cada gh pr merge por separado."

  # Argumentos hasta el primer ; & | o salto de línea, separados respetando comillas con xargs
  # (no ejecuta nada). Comillas sin cerrar: no se pueden leer, se bloquea.
  resto=${cmd#*gh pr merge}
  resto=${resto%%[;&|]*}
  resto=${resto%%$'\n'*}
  args=()
  if [ -n "${resto//[[:space:]]/}" ]; then
    lista=$(printf '%s' "$resto" | xargs -n1 printf '%s\n' 2>/dev/null) ||
      bloquear "no pude leer los argumentos de gh pr merge (¿comillas sin cerrar?)."
    while IFS= read -r a; do args+=("$a"); done <<< "$lista"
  fi

  # Flags: se saltan los valores de los que llevan uno; el resto es el número (o rama) del PR.
  target="" posicionales=0 salta=0
  for a in ${args[@]+"${args[@]}"}; do
    if [ "$salta" = 1 ]; then salta=0; continue; fi
    case "$a" in
      --admin) bloquear "--admin salta las protecciones de rama." ;;
      --auto|--auto=*) bloquear "sin --auto: GitHub mergearía después, con un estado del PR que este hook no revisó. Mergea cuando CI esté en verde." ;;
      --delete-branch|--delete-branch=*) echo "$msg_borrado" >&2; exit 2 ;;
      --repo|--repo=*) bloquear "gh pr merge en otro repositorio (-R/--repo)." ;;
      --author-email|--body|--body-file|--match-head-commit|--subject) salta=1 ;;
      --*) ;;
      -*)
        case "$a" in
          -R*) bloquear "gh pr merge en otro repositorio (-R/--repo)." ;;
          -*[!A-Za-z]*) ;;                  # flag corto con valor pegado (-t7, -Fnotas.md)
          *R*) bloquear "gh pr merge en otro repositorio (-R/--repo)." ;;
          *d*) echo "$msg_borrado" >&2; exit 2 ;;
          *[AbFt]) salta=1 ;;               # el último flag corto del grupo espera un valor
        esac ;;
      *) posicionales=$((posicionales + 1)); target=$a ;;
    esac
  done
  [ "$posicionales" -gt 1 ] && bloquear "no pude identificar un único PR en gh pr merge ($posicionales argumentos sin flag)."

  # Reglas de .claude/rutas-gobierno.txt (formato explicado en el propio archivo).
  archivo_reglas="$(dirname "$0")/../rutas-gobierno.txt"
  if [ ! -f "$archivo_reglas" ] || [ ! -r "$archivo_reglas" ] || ! texto_reglas=$(cat "$archivo_reglas" 2>/dev/null); then
    bloquear "no pude leer .claude/rutas-gobierno.txt; sin esa lista no se puede verificar el PR."
  fi
  reglas=()
  while IFS= read -r r; do
    r=${r//$'\r'/}
    r="${r#"${r%%[![:space:]]*}"}"
    r="${r%"${r##*[![:space:]]}"}"
    case "$r" in ''|'#'*) continue ;; esac
    case "${r#\*\*/}" in *'*'*) bloquear "regla no soportada en .claude/rutas-gobierno.txt: $r" ;; esac
    reglas+=("$(minusculas "$r")")
  done <<< "$texto_reglas"
  [ "${#reglas[@]}" -gt 0 ] || bloquear ".claude/rutas-gobierno.txt no tiene reglas; no se puede verificar el PR."

  # coincide <ruta en minúsculas>: imprime la regla que la cubre, o sale con 1.
  coincide() {
    local p=$1 r x
    for r in "${reglas[@]}"; do
      case "$r" in
        '**/'*/) x=${r#\*\*/}; case "$p" in "$x"*|*/"$x"*) printf '%s' "$r"; return 0 ;; esac ;;
        '**/'*) x=${r#\*\*/}; case "$p" in "$x"|*/"$x") printf '%s' "$r"; return 0 ;; esac ;;
        */) case "$p" in "$r"*) printf '%s' "$r"; return 0 ;; esac ;;
        *) if [ "$p" = "$r" ]; then printf '%s' "$r"; return 0; fi ;;
      esac
    done
    return 1
  }

  # Consulta 1: número, base y archivos del PR (gh devuelve como máximo 100 archivos).
  sel=()
  [ -n "$target" ] && sel=("$target")
  datos=$(gh pr view ${sel[@]+"${sel[@]}"} --json number,baseRefName,changedFiles,files \
    --jq '.number, .baseRefName, .changedFiles, (.files|length), .files[].path' 2>/dev/null) ||
    bloquear "no pude consultar el PR con gh pr view${target:+ $target}; sin la lista de archivos no se puede verificar."
  datos=${datos//$'\r'/}
  lineas=()
  while IFS= read -r l; do lineas+=("$l"); done <<< "$datos"
  numero=${lineas[0]:-} base=${lineas[1]:-} total=${lineas[2]:-} devueltos=${lineas[3]:-}
  for v in "$numero" "$total" "$devueltos"; do
    case "$v" in ''|*[!0-9]*) bloquear "respuesta inesperada de gh pr view${target:+ $target}; no se puede verificar." ;; esac
  done
  if [ "$base" != "staging" ]; then
    bloquear "solo puedes mergear PRs con base staging (base detectada: ${base:-desconocida}). Usa: gh pr merge <numero> --squash. El merge a main lo hace Leonardo."
  fi
  [ "$total" -gt 0 ] || bloquear "el PR #$numero figura sin archivos; no se puede verificar."
  rutas=("${lineas[@]:4}")
  if [ "$devueltos" -ne "$total" ] || [ "${#rutas[@]}" -ne "$devueltos" ]; then
    bloquear "lista incompleta de archivos del PR #$numero ($devueltos de $total); no se puede verificar."
  fi

  # Consulta 2: nombres anteriores de archivos renombrados (files solo trae la ruta nueva).
  anteriores=$(gh api "repos/{owner}/{repo}/pulls/$numero/files" --paginate \
    --jq '.[] | select(.previous_filename) | .previous_filename' 2>/dev/null) ||
    bloquear "no pude consultar los renombres del PR #$numero con gh api; no se puede verificar."
  anteriores=${anteriores//$'\r'/}
  if [ -n "$anteriores" ]; then
    while IFS= read -r l; do rutas+=("$l"); done <<< "$anteriores"
  fi

  for ruta in "${rutas[@]}"; do
    if regla=$(coincide "$(minusculas "$ruta")"); then
      bloquear "el PR #$numero toca la ruta de gobierno $ruta (regla $regla de .claude/rutas-gobierno.txt): lo mergea Leonardo, también a staging."
    fi
  done
fi
exit 0
