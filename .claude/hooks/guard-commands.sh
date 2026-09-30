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

# Credenciales e identidad del agente (cuenta-agente). Modelo de amenaza: errores del agente. El
# agente trabaja como talos-bot-leon con GH_CONFIG_DIR apuntando a ~/.talos-gh (fuera del repo), donde
# vive su token; la configuración sale de .claude/settings.local.json. Se bloquea lo que un agente
# haría por costumbre y expondría una credencial, cambiaría de cuenta, tocaría el Credential Manager
# de Leonardo (git credential-manager, salvo github list) o aprobaría un PR.
# Límites conocidos de esta sección y de la identidad de talos-bot-leon (C3 y C4 de cuenta-agente), que
# no se persiguen porque son sintaxis de shell y no errores comunes; el servidor (CODEOWNERS,
# protección de ramas, el autor no aprueba su PR) es el control efectivo:
# - un ; & | dentro de comillas parte el análisis y esconde los flags que siguen:
#   gh pr review 5 --body "R&D ok" --approve, gh api ... --jq '.a | .b' -X DELETE;
# - bash -c "git commit ..." o bash -c "gh pr create ..." no se detectan como escritura.
# Auditoría del intento 3 (sin intento 4, por decisión de Leonardo; se documentan aquí y en el PR, y
# los de identidad se verifican a mano en los pasos c, f y g de SETUP.md):
# - imprimir el entorno con espacios o comillas que el análisis por palabras no ve: export  -p (dos
#   espacios), env FOO="a b", env > archivo, env 2>&1 | grep X, ( env ). Sin token en el entorno
#   (paso f) no exponen una credencial;
# - git push: sin remoto ni --repo se asume origin (no se miran branch.<rama>.pushRemote ni
#   remote.pushDefault) y el remoto se resuelve en el directorio del hook (o en el de git -C, desde
#   A1), no en el de un cd previo. El paso f exige un solo remoto, origin, en HTTPS;
# - git push (remoto-git-push): las comillas se quitan primero las dobles y después las simples, así
#   que una " dentro de un valor entre comillas simples antes del git (V='a"b' git push "x") esconde
#   el push; y las opciones largas solo se reconocen con el nombre completo (--push-opt o --rep=,
#   prefijos que git acepta, no se leen como opciones con valor);
# - C4 compara el nombre del autor y del committer, no el email (el paso f lo verifica con git var);
# - C4 revisa git commit, git push, los gh pr que escriben, gh api de escritura y, desde A1, gh repo
#   create, new, edit, rename, archive, unarchive y sync; gh issue, gh run
#   rerun, gh workflow run, gh label y gh release no se revisan, y gh api .../reviews con
#   event=APPROVE no se bloquea como aprobación (sale como talos-bot-leon y el servidor lo acota).
bloqueo() { echo "Bloqueado por protocolo ($1): $2" >&2; exit 2; }
# I: inicio de una invocación. F: opciones (con su valor) entre gh o git y el subcomando, o entre
# el grupo y el subcomando (gh -R o/r pr review, gh pr -R o/r review, gh --hostname x auth token).
I='(^|[;&|( `])'
F='( +-[^ ;&|]+( +[^- ;&|][^ ;&|]*)?)*'
# GIT: git como palabra, también con ruta (/usr/bin/git, C:\...\git) o como git.exe (A1).
GIT='([^ ;&|]*[/\\])?git(\.exe)?'
sin_plantilla=${cmd//settings.local.example/}
if printf '%s' "$sin_plantilla" | grep -Eq 'GH_TOKEN|GITHUB_TOKEN|gh[pousr]_|github_pat_|oauth_token|settings\.local|\.talos-gh|hosts\.yml'; then
  bloqueo credenciales "el comando nombra un token o un archivo de credenciales (GH_TOKEN, GITHUB_TOKEN, oauth_token, prefijos ghp_ y similares, settings.local.json, ~/.talos-gh). Nómbralos en texto, nunca en un comando."
fi
# Sesión de Railway de Leonardo (T3a): ~/.railway/config.json guarda su token de la CLI, y
# RAILWAY_TOKEN o RAILWAY_API_TOKEN serían tokens de proyecto o de cuenta. El .railway/ del repo
# (railway.ts de IaC) sí se puede leer.
# Se revisa una copia con las barras invertidas pasadas a / (C:\Users\x\.railway\config.json).
sesion_rw=${cmd//\\//}
if printf '%s' "$sesion_rw" | grep -Eq 'RAILWAY_(API_)?TOKEN|~/\.railway|\$\{?HOME\}?/\.railway|/(Users|home)/[^/ ]+/\.railway|\.railway/config\.json|USERPROFILE%?\}?/\.railway'; then
  bloqueo credenciales "el comando nombra la sesión o un token de Railway (~/.railway, .railway/config.json, RAILWAY_TOKEN, RAILWAY_API_TOKEN). Nómbralos en texto, nunca en un comando."
fi
if printf '%s\n' "$cmd" | grep -Eq "${I}gh$F +auth$F +(token|git-credential)([^[:alnum:]_-]|\$)|${I}gh$F +auth$F +status[^;&|]*( -[a-z]*t[a-z]*( |\$)| --show-token)|${I}git( +[^ ;&|]+)* +credential +(fill|approve|reject)"; then
  bloqueo credenciales "el comando imprime una credencial (gh auth token, gh auth status -t, gh auth git-credential, git credential fill)."
fi
# git credential-manager (lecciones, T2): login, logout, get, store, erase o configure tocan el
# Credential Manager de Leonardo, donde vive su credencial de git. El agente solo puede listar las
# cuentas (git credential-manager github list). Cubre git credential-manager con opciones globales de
# git antes (-C dir, -c k=v, como $F; git grep credential-manager no cuenta), git-credential-manager
# con ruta completa, y los sufijos -core y .exe. En cada segmento se quita un comentario (# precedido
# de espacio), y solo pasa si hay una sola invocación y va seguida de github list.
# Límites: el texto "git credential-manager" dentro de un --title o un -m también cuenta (usa
# --body-file y -F); powershell.exe -Command "..." y $(...) no se ven (fuera del modelo de amenaza).
gcm="(${I}git$F +credential-manager|(${I}|[/\\\\])git-credential-manager)(-core)?(\\.exe)?([^[:alnum:]_.-]|\$)"
if printf '%s\n' "$cmd" | grep -Eq "$gcm"; then
  while IFS= read -r seg; do
    s=" ${seg%%[[:space:]]#*} "
    printf '%s\n' "$s" | grep -Eq "$gcm" || continue
    n=$(printf '%s\n' "$s" | grep -Eo 'credential-manager' | wc -l)
    { [ $((n)) -eq 1 ] && printf '%s\n' "$s" | grep -Eq "credential-manager(-core)?(\\.exe)? +github +list( [^;&|]*)?\$"; } ||
      bloqueo credenciales "git credential-manager toca el Credential Manager de Leonardo; el agente solo puede correr git credential-manager github list."
  done <<< "$(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')"
fi
# env_imprime <segmento>: el segmento imprime variables de entorno: set, export, declare o typeset
# sin argumentos; printenv sin una variable (solo opciones); o env sin un comando que correr (solo
# opciones o VAR=x).
env_imprime() {
  local s=$1 t salta=0 prog
  case "$s" in
    set|export|'export -p'|declare|'declare -p'|'declare -x'|'declare -px'|'declare -xp'|typeset|'typeset -p'|'typeset -x') return 0 ;;
    printenv|printenv\ *|env|env\ *) ;;
    *) return 1 ;;
  esac
  set -f
  set -- $s
  set +f
  prog=$1
  shift
  for t in "$@"; do
    if [ "$salta" = 1 ]; then salta=0; continue; fi
    case "$prog:$t" in
      env:-u|env:--unset|env:-C|env:--chdir|env:-S|env:--split-string) salta=1 ;;
      *:-*) ;;
      env:*=*) ;;
      *) return 1 ;;
    esac
  done
  return 0
}
# env_vacia <segmento>: env con -i, --ignore-environment o - entre sus propias opciones (antes del
# comando que corre): vacía el entorno y con él la identidad del agente. Un -i del comando que env
# corre (env LC_ALL=C sed -i ...) no cuenta.
env_vacia() {
  local t salta=0
  case "$1" in env\ *) ;; *) return 1 ;; esac
  set -f
  set -- $1
  set +f
  shift
  for t in "$@"; do
    if [ "$salta" = 1 ]; then salta=0; continue; fi
    case "$t" in
      -i|--ignore-environment|-) return 0 ;;
      -u|--unset|-C|--chdir|-S|--split-string) salta=1 ;;
      -*|*=*) ;;
      *) return 1 ;;
    esac
  done
  return 1
}
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  seg="${seg%"${seg##*[![:space:]]}"}"
  seg=${seg#\(}
  env_imprime "$seg" && bloqueo credenciales "el comando imprime variables de entorno ($seg)."
  env_vacia "$seg" && bloqueo identidad "el comando vacía el entorno (env -i) y con él la identidad del agente."
done <<< "$(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')"
if printf '%s\n' "$cmd" | grep -Eq "GH_CONFIG_DIR|GIT_CONFIG_|${I}gh$F +auth$F +(login|logout|switch|refresh|setup-git)([^[:alnum:]_-]|\$)|${I}git( +[^;&|]*)? +(-c +[^;&|]*credential|config [^;&|]*credential)"; then
  bloqueo identidad "el comando cambiaría la cuenta de GitHub del agente (gh auth login/switch/logout/refresh/setup-git, GH_CONFIG_DIR, GIT_CONFIG_*, credential.helper). La identidad del agente sale de .claude/settings.local.json."
fi
if printf '%s\n' "$cmd" | grep -Eq "${I}gh$F +pr$F +review[^;&|]*( --approve| -[A-Za-z]*a[A-Za-z]*( |\$))"; then
  bloqueo aprobación "el agente nunca aprueba PRs; la aprobación de code owner es de Leonardo."
fi

# Analiza las invocaciones de git y responde una sola palabra: force, todas, main, borrado o limpio.
# - force: push forzado en cualquier forma y posición. --force, --force-with-lease,
#   --force-if-includes y sus abreviaturas desde --f; -f solo o combinado (-uf, -fu); --mirror y
#   sus abreviaturas desde --m (fuerza updates); refspecs con + (git push origin +rama);
#   -c remote.<r>.push=+... o mirror=, y lo mismo por GIT_CONFIG_* antes de git.
# - todas (A1): git push --all o --branches (y sus abreviaturas desde --a y --b), o un refspec con
#   *: empujarían todas las ramas, main y staging incluidas.
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
            else if (prefijo(op, "--all") || prefijo(op, "--branches") || (t !~ /^-/ && t ~ /\*/))
              marcar("todas")
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
  todas)
    echo "Bloqueado por protocolo (push de todas las ramas: --all, --branches o refspec con *). Empuja cada rama por su nombre." >&2
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

# leer_push <segmento>: lee un git push respetando comillas, con xargs (no ejecuta nada). Deja en
# remoto el primer posicional después de push, en repo el valor de --repo, en dir_c el directorio de
# -C (combinado si hay varios) y en refs los posicionales que siguen al remoto. Sale con 0 si leyó un
# git push, con 1 si no lo encontró y con 2 si no pudo separar los argumentos (comillas sin cerrar).
leer_push() {
  local lista t estado=0 sigue=""
  remoto="" repo="" dir_c="" refs=()
  lista=$(printf '%s' "$1" | xargs printf '%s\n' 2>/dev/null) || return 2
  while IFS= read -r t; do
    t=${t#\(}                           # subshell: (git push) o (cd x && git push)
    t=${t%\)}
    if [ -n "$sigue" ]; then
      case "$sigue" in
        repo) repo=$t ;;
        dir) case "$t" in /*|[A-Za-z]:*) dir_c=$t ;; *) dir_c=${dir_c:+$dir_c/}$t ;; esac ;;
      esac
      sigue=""
      continue
    fi
    if [ "$estado" = 0 ]; then
      case "$t" in git|*/git|git.exe|*/git.exe) estado=1 ;; esac
    elif [ "$estado" = 1 ]; then
      case "$t" in
        -C) sigue=dir ;;
        -c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix|--attr-source) sigue=valor ;;
        -*) ;;
        push) estado=2 ;;
        *) estado=0 ;;
      esac
    else
      case "$t" in
        [0-9]*[\<\>]*|[\<\>]*)          # redirección: >archivo, 2>err, o el operador solo
          case "$t" in *[!0-9\<\>]*) ;; *) sigue=valor ;; esac ;;
        -o|--push-option|--receive-pack|--exec) sigue=valor ;;
        --repo) sigue=repo ;;
        --repo=*) repo=${t#--repo=} ;;
        --*) ;;
        -*o) sigue=valor ;;             # grupo de flags cortos que termina en -o (-uo x)
        -*) ;;                          # otros flags; -oX lleva el valor pegado
        *) if [ -z "$remoto" ]; then remoto=$t; else refs+=("$t"); fi ;;
      esac
    fi
  done <<< "$lista"
  [ "$estado" = 2 ]
}

# Rama staging (A1). En un repo nuevo de la organización, staging no existe hasta después del merge
# del framework a main, y el ruleset de staging no frena su creación (do_not_enforce_on_create). Si
# naciera antes, en el commit del README, el primer PR a staging entraría sin code owner (CODEOWNERS
# se lee de la rama base) y con 0 aprobaciones. Por eso un git push cuyo destino sea staging
# (staging, X:staging, X:refs/heads/staging) solo pasa como git push origin origin/main:staging (o
# :refs/heads/staging), y solo si origin/main del directorio del push (o de -C) ya tiene
# .github/CODEOWNERS. Una vez creada, el ruleset rechaza los pushes directos a staging.
# Límites (fuera del modelo de amenaza): git push sin refspec o con HEAD estando en una rama local
# llamada staging (el flujo no la crea), y los límites de lectura de C4 (cd previo, bash -c).
if [[ ${cmd,,} == *push*staging* ]]; then
  while IFS= read -r seg; do
    [[ $seg == *push* ]] || continue
    printf '%s\n' " $seg " | sed -E "s/\"[^\"]*\"/ /g; s/'[^']*'/ /g" | grep -Eq "${I}$GIT$F +push([^[:alnum:]_-]|\$)" || continue
    leer_push "$seg"
    case $? in
      0) ;;
      2) if [[ ${seg,,} == *staging* ]]; then bloqueo staging "no pude leer los argumentos de git push (¿comillas sin cerrar?)."; fi; continue ;;
      *) continue ;;
    esac
    for r in ${refs[@]+"${refs[@]}"}; do
      r=${r,,}
      case "${r##*:}" in staging|refs/heads/staging) ;; *) continue ;; esac
      case "$r" in
        origin/main:staging|origin/main:refs/heads/staging) ;;
        *) bloqueo staging "staging solo se crea desde main: git push origin origin/main:refs/heads/staging, después del merge del framework a main. Los cambios llegan a staging por PR." ;;
      esac
      [ "${remoto:-${repo:-origin}}" = origin ] ||
        bloqueo staging "staging solo se crea en origin: git push origin origin/main:refs/heads/staging."
      # En Git Bash, sin MSYS_NO_PATHCONV la ruta origin/main:.github/CODEOWNERS se convierte en
      # origin\main;.github\CODEOWNERS; con ella, git -C no convierte /c/... ni /tmp/... para git.exe.
      # Por eso se entra al directorio con cd (bash lo resuelve) y git corre sin -C.
      ( cd "${dir_c:-.}" 2>/dev/null && MSYS_NO_PATHCONV=1 git cat-file -e origin/main:.github/CODEOWNERS 2>/dev/null ) ||
        bloqueo staging "origin/main de ${dir_c:-este repo} no tiene .github/CODEOWNERS (¿falta el merge del framework a main o un git fetch?); staging se crea después de ese merge."
    done
  done <<< "$(printf '%s\n' "$cmd" | sed -E 's/[0-9]*[<>]&[0-9]*-?/ /g; s/&>>?/ > /g; s/>\|/>/g' | tr ';&|' '\n\n\n')"
fi

deny_patterns=(
  'git reset --hard'
  'git clean -f'
  'rm -rf'
  'DROP (TABLE|DATABASE|SCHEMA)'
  'TRUNCATE'
  'cat .*\.env'
  'echo \$[A-Za-z_]*(TOKEN|KEY|SECRET|PASSWORD)'
  'curl .* (-d|--data|-X POST|-X PUT|-X DELETE)'
)
for p in "${deny_patterns[@]}"; do
  if printf '%s' "$cmd" | grep -Eiq "$p"; then
    echo "Bloqueado por protocolo (patrón: $p). Si de verdad hace falta, pídele a Leonardo que lo ejecute él." >&2
    exit 2
  fi
done

# Railway (T3a): el agente solo corre lecturas. Todo comando de railway que escriba (deploys,
# servicios, ambientes, dominios, variables, config apply, login) lo corre Leonardo en su terminal
# (CLAUDE.md: OK explícito para cualquier railway que no sea de lectura). Lista de permitidos, no de
# prohibidos: la CLI suma subcomandos casi cada semana. Un segmento invoca railway si su primera
# palabra es railway, una ruta a railway o railway.exe, o npx con @railway/cli. Antes se saltan "(",
# las palabras clave de shell (if, then, else, elif, do, while, until, !, {), VAR=valor, sudo, env,
# command, exec, builtin y nohup, y los envoltorios con sus opciones y su número o duración (time,
# timeout, xargs, watch, nice, ionice, stdbuf, winpty). Un "railway" como argumento (grep, echo, cat
# .railway/railway.ts) no cuenta. Límites (fuera del modelo de amenaza): bash -c "railway up",
# env -u X railway up, sudo -u x railway up, variables y alias.
# railway_args <segmento>: 0 si el segmento invoca railway; deja sus argumentos en rw_args.
railway_args() {
  local t primero=1 npx=0 envoltorio=0
  rw_args=()
  set -f
  # shellcheck disable=SC2086
  set -- $1
  set +f
  while [ $# -gt 0 ]; do
    t=${1#\(}
    shift
    if [ "$primero" = 1 ]; then
      case "$t" in
        '') continue ;;
        if|then|else|elif|do|while|until|'!'|'{') continue ;;
        *=*|sudo|env|command|exec|builtin|nohup) continue ;;
        time|timeout|xargs|watch|nice|ionice|stdbuf|winpty) envoltorio=1; continue ;;
        npx|pnpx|bunx) npx=1; continue ;;
        -*) { [ "$npx" = 1 ] || [ "$envoltorio" = 1 ]; } && continue; return 1 ;;
        railway|*/railway|railway.exe|*/railway.exe|*\\railway.exe) primero=0; continue ;;
        @railway/cli|@railway/cli@*) [ "$npx" = 1 ] && { primero=0; continue; }; return 1 ;;
        *)
          # El número o la duración de un envoltorio (timeout 600, nice -n 10, xargs -n 1).
          if [ "$envoltorio" = 1 ] && [ "${t#[0-9]}" != "$t" ] && [ -z "${t//[0-9.smhd]/}" ]; then continue; fi
          return 1 ;;
      esac
    fi
    rw_args+=("${t%)}")
  done
  [ "$primero" = 0 ]
}
# railway_lectura: 0 si rw_args es una lectura. El subcomando y el sub-subcomando son las dos
# primeras palabras que no empiezan con -, antes de "--".
# La ayuda (--help, -h, --version, -V) no ejecuta nada. Cuenta antes de "--" y dentro de las dos
# primeras palabras. En run, local, ssh, shell, connect, dev y code, lo que sigue al subcomando es
# del comando hijo (railway ssh -- df -h, railway ssh free -h): ahí solo cuenta justo después.
railway_lectura() {
  local a sub="" sub2="" pos=0 i=0 isub=0 hijo=0
  for a in ${rw_args[@]+"${rw_args[@]}"}; do
    i=$((i + 1))
    [ "$a" = -- ] && break
    case "$a" in
      --help|-h|--version|-V)
        if [ "$hijo" = 1 ]; then
          [ "$i" -eq $((isub + 1)) ] && return 0
        elif [ "$pos" -le 2 ]; then
          return 0
        fi ;;
      -*) ;;
      *)
        pos=$((pos + 1))
        if [ "$pos" = 1 ]; then
          isub=$i
          case "$a" in run|local|ssh|shell|connect|dev|develop|code) hijo=1 ;; esac
        fi ;;
    esac
  done
  for a in ${rw_args[@]+"${rw_args[@]}"}; do
    [ "$a" = -- ] && break
    case "$a" in -*) continue ;; esac
    if [ -z "$sub" ]; then sub=$a; else sub2=$a; break; fi
  done
  case "$sub" in
    ""|help|status|whoami|logs|list|ls|metrics|docs) return 0 ;;
    environment|env) case "$sub2" in link|list|ls|config|show|info) return 0 ;; esac ;;
    service) case "$sub2" in list|ls|status|logs) return 0 ;; esac ;;
    domain) case "$sub2" in list|ls|status) return 0 ;; esac ;;
    deployment|deployments|project|projects|volume|volumes) case "$sub2" in list|ls) return 0 ;; esac ;;
    variable|variables|vars|var) case "$sub2" in ""|list|ls) return 0 ;; esac ;;
    usage) case "$sub2" in ""|projects) return 0 ;; esac ;;
    api) case "$sub2" in schema|search|describe) return 0 ;; esac ;;
    config)
      case "$sub2" in
        plan) printf ' %s ' "${rw_args[*]}" | grep -Eq ' --(show-values|decrypt-variables)(=| )' || return 0 ;;
        migrate) printf ' %s ' "${rw_args[*]}" | grep -Eq ' --(apply|delete-files)(=| )' || return 0 ;;
      esac ;;
  esac
  return 1
}
while IFS= read -r seg; do
  railway_args "$seg" || continue
  railway_lectura ||
    bloqueo Railway "el agente solo corre lecturas de railway (status, logs, list, environment link <nombre>, variables con solo nombres, config plan, --help). Este comando escribe o no está en la lista: lo corre Leonardo en su terminal."
  # Variables: solo nombres, nunca valores (salvo la ayuda).
  primer="" ayuda=0
  for a in ${rw_args[@]+"${rw_args[@]}"}; do
    case "$a" in
      --help|-h) ayuda=1 ;;
      -*) ;;
      *) [ -z "$primer" ] && primer=$a ;;
    esac
  done
  case "$primer" in
    variable|variables|vars|var)
      [ "$ayuda" = 1 ] || printf '%s' "$cmd" | grep -Eq "cut -d= -f1|jq (-r )?'keys'" ||
        bloqueo Railway "railway variables solo nombres: lista con railway variables --kv | cut -d= -f1." ;;
  esac
done <<< "$(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')"
# Identidad de talos-bot-leon (C4 de cuenta-agente). Se activa cuando existe .claude/identidad-agente.txt
# con el login esperado: desde ahí, sin la identidad de talos-bot-leon se bloquean commits, push y
# escrituras en GitHub en lugar de volver en silencio a la cuenta de Leonardo. Sin el archivo no se
# exige (arranque, antes de conectar talos-bot-leon).
archivo_identidad="$(dirname "$0")/../identidad-agente.txt"
if [ -e "$archivo_identidad" ]; then
  # Cada segmento (separado por ; & | o salto de línea) se clasifica por separado: una invocación
  # con --help no escribe, pero no borra una escritura detectada en otro segmento. Antes de partir se
  # normalizan las redirecciones con & (2>&1, >&2, &>, >|), como en analizar_git: ese & no separa.
  escribe_git=0 escribe_gh=0 empuja=0 pushes=()
  while IFS= read -r seg; do
    [ -n "${seg//[[:space:]]/}" ] || continue
    s=" $seg "
    if printf '%s\n' "$s" | grep -Eq "${I}$GIT$F +(commit|push)([^[:alnum:]_-]|\$)"; then
      escribe_git=1
      # El texto entre comillas no es una invocación: un "git push" dentro de un -m o un --title no
      # cuenta como push.
      if printf '%s\n' "$s" | sed -E "s/\"[^\"]*\"/ /g; s/'[^']*'/ /g" | grep -Eq "${I}$GIT$F +push([^[:alnum:]_-]|\$)"; then
        empuja=1
        pushes+=("$seg")
      fi
    fi
    printf '%s\n' "$s" | grep -Eq "${I}gh( |\$)" || continue
    # --help o -h solo cuentan como token fuera de comillas: en un --title o --body son texto. En gh
    # repo create, new y edit, -h es --homepage (A1): ahí solo cuenta --help.
    ayuda=' (--help|-h)( |$)'
    printf '%s\n' "$s" | grep -Eq "${I}gh$F +repo$F +(create|new|edit)([^[:alnum:]_-]|\$)" && ayuda=' --help( |$)'
    printf '%s\n' "$s" | sed -E "s/\"[^\"]*\"/ /g; s/'[^']*'/ /g" | grep -Eq "$ayuda" && continue
    if printf '%s\n' "$s" | grep -Eq "${I}gh$F +pr$F +(create|new|merge|review|comment|edit|close|reopen|ready)([^[:alnum:]_-]|\$)"; then
      escribe_gh=1
    elif printf '%s\n' "$s" | grep -Eq "${I}gh$F +repo$F +(create|new|edit|rename|archive|unarchive|sync)([^[:alnum:]_-]|\$)"; then
      escribe_gh=1
    elif printf '%s\n' "$s" | grep -Eq "${I}gh$F +api( |\$)"; then
      # gh api escribe con campos (-f, -F, --field, --raw-field, --input, que implican POST) o con
      # graphql; y con un método distinto de GET. Cada -X/--method cuenta (gh usa el último): si
      # alguno no es GET, o no se puede leer (por ejemplo -X "$M"), es escritura.
      if printf '%s\n' "$s" | grep -Eq ' (-[fF]|--field|--raw-field|--input)| graphql( |$)'; then
        escribe_gh=1
      else
        metodos=$(printf '%s\n' "$s" | grep -Eo ' (-X|--method)' | wc -l)
        gets=$(printf '%s\n' "$s" | grep -Eio " (-X|--method)( +|=)?[\"']?get[\"']?( |\$)" | wc -l)
        [ $((metodos)) -gt $((gets)) ] && escribe_gh=1
      fi
    fi
  done <<< "$(printf '%s\n' "$cmd" | sed -E 's/[0-9]*[<>]&[0-9]*-?/ /g; s/&>>?/ > /g; s/>\|/>/g' | tr ';&|' '\n\n\n')"
  if [ "$escribe_git" = 1 ] || [ "$escribe_gh" = 1 ]; then
    esperado=$(tr -d '[:space:]' < "$archivo_identidad" 2>/dev/null)
    falta="falta la identidad de ${esperado:-la cuenta del agente} (.claude/settings.local.json)"
    [ -n "$esperado" ] || bloqueo identidad "$falta: .claude/identidad-agente.txt está vacío o no se puede leer."
    { [ -n "${GH_CONFIG_DIR:-}" ] && [ -n "${GIT_CONFIG_COUNT:-}" ]; } ||
      bloqueo identidad "$falta: GH_CONFIG_DIR o GIT_CONFIG_COUNT no están definidas en la sesión."
    { [ "${GIT_AUTHOR_NAME:-}" = "$esperado" ] && [ "${GIT_COMMITTER_NAME:-}" = "$esperado" ]; } ||
      bloqueo identidad "$falta: el autor o el committer de los commits no es $esperado."
    if [ "$empuja" = 1 ]; then
      # git push: la credencial tiene que salir de gh (talos-bot-leon) y no del Git Credential Manager de
      # Leonardo. Se exige la configuración exacta de la plantilla, que el helper efectivo para
      # github.com sea gh y que el remoto sea HTTPS sin usuario (por SSH saldría la llave de Leonardo).
      clave='credential.https://github.com.helper'
      { [ "${GIT_CONFIG_COUNT:-}" = 2 ] && [ "${GIT_CONFIG_KEY_0:-}" = "$clave" ] &&
        [ "${GIT_CONFIG_VALUE_0+definida}" = definida ] && [ -z "${GIT_CONFIG_VALUE_0-}" ] &&
        [ "${GIT_CONFIG_KEY_1:-}" = "$clave" ] && [ "${GIT_CONFIG_VALUE_1:-}" = '!gh auth git-credential' ]; } ||
        bloqueo identidad "$falta: la configuración del helper de credenciales no es la de la plantilla (GIT_CONFIG_COUNT, GIT_CONFIG_KEY_0/1, GIT_CONFIG_VALUE_0/1)."
      efectivo=$(git config --get-urlmatch credential.helper https://github.com 2>/dev/null) || efectivo=""
      [ "${efectivo//$'\r'/}" = '!gh auth git-credential' ] ||
        bloqueo identidad "$falta: el helper de credenciales efectivo para github.com es '${efectivo:-ninguno}', no gh."
      for p in "${pushes[@]}"; do
        # El remoto es el primer posicional después de push; si no hay, el valor de --repo; si no,
        # origin (como git). Se resuelve en el directorio de git -C, si lo hay (A1).
        leer_push "$p"
        case $? in
          0) ;;
          2) bloqueo identidad "no pude leer los argumentos de git push (¿comillas sin cerrar?); escríbelo en una sola línea, sin ; & | dentro de comillas." ;;
          *) bloqueo identidad "no pude leer el git push ($p); escríbelo como git push <remoto> <rama>." ;;
        esac
        [ -z "$dir_c" ] || [ -d "$dir_c" ] ||
          bloqueo identidad "el directorio de git -C ($dir_c) no existe; no se puede leer su remoto. Usa la ruta literal, sin variables ni ~."
        remoto=${remoto:-$repo}
        remoto=${remoto:-origin}
        case "$remoto" in
          *://*|*@*) url=$remoto ;;
          *) url=$(git -C "${dir_c:-.}" remote get-url --push "$remoto" 2>/dev/null) || url="" ;;
        esac
        url=${url//$'\r'/}
        case "$url" in
          https://github.com/*) ;;
          *) bloqueo identidad "$falta: el remoto '$remoto' ($url) no es HTTPS de github.com sin usuario; por SSH o con usuario el push no sale como $esperado." ;;
        esac
      done
    fi
    if [ "$escribe_gh" = 1 ] || [ "$empuja" = 1 ]; then
      login=$(gh api user --jq .login 2>/dev/null) || login=""
      login=${login//$'\r'/}
      [ "$login" = "$esperado" ] || bloqueo identidad "$falta: GitHub responde como ${login:-desconocido}, no como $esperado."
    fi
  fi
fi

# Repos en la organización (A1). En el plan Team de GitHub no se puede restringir a los miembros a
# crear solo repos privados: este bloque es la barrera principal. El agente crea repos solo en la
# organización de .claude/pipeline.conf (org), privados y con el equipo de pipeline.conf (equipo); no
# cambia la visibilidad, no hace fork, no borra ni transfiere repos, y no abre un repo a terceros
# (colaboradores, invitaciones, deploy keys, webhooks, Pages). Es una lista de permitidos: lo que no
# se puede leer se bloquea.
# Cómo lee el comando: partir corta en ; & | y saltos de línea fuera de comillas, xargs separa los
# argumentos respetando comillas (no ejecuta nada) y leer_gh busca la palabra gh (gh.exe, una ruta, o
# tras $( ( o `). Red de seguridad: en el texto sin comillas ni barras invertidas se cuentan las
# apariciones de gh ... repo create|new|edit|fork|delete|deploy-key, de gh ... api y de
# gh ... alias|extension; si alguna supera las invocaciones leídas (bash -c "...", "$(...)"), se
# bloquea. Costo aceptado: ese texto dentro de un --title, un -m o un -f body= también se bloquea (usa --body-file,
# git commit -F o gh api -F body=@archivo).
# Límites (fuera del modelo de amenaza): alias y extensiones ya instalados en la configuración de gh
# del bot (hoy solo el alias co de fábrica), GH_HOST o GH_REPO exportados en un comando anterior, y
# eval o bash -c con texto armado en variables.
# Todo con expansiones y [[ =~ ]] de bash, sin procesos, salvo xargs y sed en los segmentos con gh.
re_gh='(^|[^[:alnum:]_.-])gh(\.exe)?([^[:alnum:]_.-]|$)'
g_gh='(^|[^[:alnum:]_.-])gh(\.exe)?( +-[^ ]+( +[^- ][^ ]*)?)*'
re_repo="$g_gh +repo( +-[^ ]+( +[^- ][^ ]*)?)* +(create|new|edit|fork|delete|deploy-key)([^[:alnum:]_-]|\$)"
re_api="$g_gh +api([^[:alnum:]_-]|\$)"
re_ext="$g_gh +(alias|extensions?|ext)([^[:alnum:]_-]|\$)"
# plano <texto>: deja en pl el texto sin comillas, con las barras invertidas como / (así una ruta de
# Windows a gh.exe sigue precedida por un separador) y con tabs y saltos de línea como espacios.
plano() { pl=${1//[\"\']/}; pl=${pl//\\//}; pl=${pl//[$'\n\t\r']/ }; }
# cuenta <texto> <regex>: deja en cnt cuántas apariciones sin solaparse hay.
cuenta() {
  local s=$1
  cnt=0
  while [[ $s =~ $2 ]]; do
    cnt=$((cnt + 1))
    s=${s#*"${BASH_REMATCH[0]}"}
  done
}
# leer_conf: org y equipo de .claude/pipeline.conf (la primera línea de cada clave).
leer_conf() {
  local k v f d=${0%/*}
  [ "$d" = "$0" ] && d=.
  f="$d/../pipeline.conf"
  org="" equipo=""
  [ -r "$f" ] || return 0
  while IFS='=' read -r k v || [ -n "$k" ]; do
    v=${v%$'\r'}
    case "$k" in
      org) [ -n "$org" ] || org=$v ;;
      equipo) [ -n "$equipo" ] || equipo=$v ;;
    esac
  done < "$f"
}
# partir <texto>: deja en segs los segmentos, cortados en ; & | y saltos de línea fuera de comillas
# y sin escapar. Un # al inicio o después de un espacio, fuera de comillas, es comentario.
partir() {
  local s=$1 out="" q="" c i=0 n=${#1} com=0
  segs=()
  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    if [ "$com" = 1 ]; then
      if [ "$c" = $'\n' ]; then com=0; segs+=("$out"); out=""; fi
      i=$((i + 1))
      continue
    fi
    if [ "$q" = "'" ]; then
      [ "$c" = "'" ] && q=""
    elif [ "$q" = '"' ]; then
      if [ "$c" = '\' ]; then out+=$c; i=$((i + 1)); c=${s:i:1}
      elif [ "$c" = '"' ]; then q=""; fi
    else
      case "$c" in
        "'"|'"') q=$c ;;
        '\') out+=$c; i=$((i + 1)); c=${s:i:1} ;;
        ';'|'&'|'|'|$'\n') segs+=("$out"); out=""; i=$((i + 1)); continue ;;
        '#') if [ -z "${out//[[:space:]]/}" ] || [[ "$out" == *[[:space:]] ]]; then com=1; i=$((i + 1)); continue; fi ;;
      esac
    fi
    out+=$c
    i=$((i + 1))
  done
  segs+=("$out")
}
# leer_gh: busca en toks la primera palabra gh y deja en gh_sub el subcomando (salta las opciones
# entre gh y el subcomando; -R y --repo llevan valor) y en gh_args lo que sigue.
leer_gh() {
  local i t n=${#toks[@]}
  gh_sub="" gh_args=()
  for ((i = 0; i < n; i++)); do
    t=${toks[i]##*\$\(}
    t=${t##*\`}
    t=${t#\(}
    case "$t" in gh|gh.exe|*/gh|*/gh.exe|*\\gh|*\\gh.exe) break ;; esac
  done
  [ "$i" -lt "$n" ] || return 1
  i=$((i + 1))
  while [ "$i" -lt "$n" ]; do
    case "${toks[i]}" in
      -R|--repo) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  gh_sub=${toks[i]:-}
  gh_args=("${toks[@]:i+1}")
}
sin_host() {
  case "$cmd" in
    *GH_HOST=*|*GH_REPO=*) bloqueo repos "$1 con GH_HOST o GH_REPO: apunta a otro servidor o repositorio." ;;
  esac
}
# revisar_create <args>: los argumentos de gh repo create o gh repo new (C1).
revisar_create() {
  local a nombre="" npos=0 priv=0 nteam=0 team="" sigue="" duenio resto
  [ $# -gt 0 ] || bloqueo repos "gh repo create sin argumentos abre el modo interactivo, que propone un repo público. Usa gh repo create $org/<nombre> --private --team $equipo."
  for a in "$@"; do [ "$a" = --help ] && return 0; done
  { [ -n "$org" ] && [ -n "$equipo" ]; } ||
    bloqueo repos "no pude leer org y equipo de .claude/pipeline.conf; sin ellos no se puede verificar gh repo create."
  sin_host "gh repo create"
  for a in "$@"; do
    if [ -n "$sigue" ]; then
      [ "$sigue" = team ] && team=$a
      sigue=""
      continue
    fi
    case "$a" in
      [0-9]*[\<\>]*|[\<\>]*)          # redirección: >archivo, 2>err, o el operador solo
        case "$a" in *[!0-9\<\>]*) ;; *) sigue=redir ;; esac ;;
      --private) priv=$((priv + 1)) ;;
      --add-readme|--disable-issues|--disable-wiki) ;;
      -d|--description|-g|--gitignore|-l|--license) sigue=valor ;;
      --description=*|--gitignore=*|--license=*) ;;
      -t|--team) sigue=team; nteam=$((nteam + 1)) ;;
      --team=*) team=${a#--team=}; nteam=$((nteam + 1)) ;;
      -*) bloqueo repos "gh repo create no admite $a. Solo: $org/<nombre> --private --team $equipo, y opcionales --add-readme, --disable-issues, --disable-wiki, -d, -g y -l." ;;
      *) npos=$((npos + 1)); nombre=$a ;;
    esac
  done
  { [ -z "$sigue" ] || [ "$sigue" = redir ]; } || bloqueo repos "gh repo create: falta el valor del último flag."
  [ "$npos" = 1 ] || bloqueo repos "gh repo create necesita un solo nombre, $org/<nombre> ($npos posicionales)."
  duenio=${nombre%%/*} resto=${nombre#*/}
  { [ "$duenio" != "$nombre" ] && [ "${duenio,,}" = "${org,,}" ] && [[ $resto =~ ^[A-Za-z0-9._-]+$ ]] &&
    [ "$resto" != . ] && [ "$resto" != .. ]; } ||
    bloqueo repos "el agente solo crea repos en $org, con el nombre $org/<nombre> (recibí '$nombre'). Sin dueño se crearía en la cuenta del bot."
  [ "$priv" = 1 ] || bloqueo repos "gh repo create necesita exactamente un --private, sin valor: el agente solo crea repos privados."
  { [ "$nteam" = 1 ] && [ "${team,,}" = "${equipo,,}" ]; } ||
    bloqueo repos "gh repo create necesita un solo --team $equipo."
}
# revisar_edit <args>: los argumentos de gh repo edit (C2).
revisar_edit() {
  local a flags=0
  for a in "$@"; do [ "$a" = --help ] && return 0; done
  for a in "$@"; do
    case "$a" in
      --visibility|--visibility=*|--accept-visibility-change-consequences|--accept-visibility-change-consequences=*)
        bloqueo repos "el agente no cambia la visibilidad de un repo (gh repo edit --visibility); lo hace Leonardo." ;;
      --default-branch|--default-branch=*)
        bloqueo repos "el agente no cambia la rama por defecto (gh repo edit --default-branch); los rulesets la protegen." ;;
      --allow-forking=false) flags=$((flags + 1)) ;;
      --allow-forking|--allow-forking=*)
        bloqueo repos "el agente no habilita forks (gh repo edit --allow-forking)." ;;
      -*) flags=$((flags + 1)) ;;
    esac
  done
  [ "$flags" -gt 0 ] || bloqueo repos "gh repo edit sin flags abre el modo interactivo, que ofrece cambiar la visibilidad."
}
# revisar_api <segmento> <args>: gh api de escritura (C4).
revisar_api() {
  local a metodo="" campos=0 archivo=0 sigue="" endpoint="" npos=0 e v
  local -a p queries=()
  for a in "$@"; do case "$a" in --help|-h) return 0 ;; esac; done
  for a in "$@"; do
    if [ -n "$sigue" ]; then
      case "$sigue" in
        metodo) metodo=$a ;;
        campo) case "$a" in query=*) queries+=("${a#query=}") ;; esac ;;
      esac
      sigue=""
      continue
    fi
    case "$a" in
      [0-9]*[\<\>]*|[\<\>]*)          # redirección: >archivo, 2>err, o el operador solo
        case "$a" in *[!0-9\<\>]*) ;; *) sigue=redir ;; esac ;;
      -X|--method) sigue=metodo ;;
      -X*) metodo=${a#-X} ;;
      --method=*) metodo=${a#--method=} ;;
      -f|-F|--field|--raw-field) campos=1; sigue=campo ;;
      -[fF]*) campos=1; v=${a#-?}; case "$v" in query=*) queries+=("${v#query=}") ;; esac ;;
      --field=*|--raw-field=*) campos=1; v=${a#*=}; case "$v" in query=*) queries+=("${v#query=}") ;; esac ;;
      --input) campos=1; archivo=1; sigue=valor ;;
      --input=*) campos=1; archivo=1 ;;
      -H|--header|-q|--jq|-t|--template|--hostname|--cache|-p|--preview) sigue=valor ;;
      -*) ;;
      *) npos=$((npos + 1)); endpoint=$a ;;
    esac
  done
  e=${endpoint,,}
  e=${e#https://api.github.com}
  e=${e#/}
  e=${e%%\?*}
  e=${e%/}
  if [ "$e" = graphql ]; then
    # La mutation se busca en todo el comando: una query armada en una variable antes (Q=...;) no
    # está en el segmento. Una query que el hook no ve (archivo, variable, $(...) o backticks) se
    # bloquea.
    [[ ${cmd_c,,} == *mutation* ]] &&
      bloqueo repos "gh api graphql con una mutation: el pipeline no usa mutations de GraphQL."
    [ "$archivo" = 1 ] && bloqueo repos "gh api graphql --input: el hook no ve la query."
    for v in ${queries[@]+"${queries[@]}"}; do
      case "$v" in
        @*|\$*|*\`*) bloqueo repos "gh api graphql con la query en un archivo, una variable, \$(...) o backticks: el hook no la ve. Escríbela literal con -f query='...'." ;;
      esac
    done
    return 0
  fi
  # Escritura: el último método no es GET o, sin método, hay campos (implican POST).
  if [ -n "$metodo" ]; then [ "${metodo,,}" = get ] && return 0; else [ "$campos" = 1 ] || return 0; fi
  sin_host "gh api de escritura"
  { [ "$npos" = 1 ] && [ -n "$e" ] && [[ $endpoint != *[\$\`]* ]]; } ||
    bloqueo repos "no pude leer el endpoint de este gh api de escritura (ninguno, varios o con \$ o backticks)."
  # Formas raras del endpoint (otro esquema o puerto, // o una / de más): no se pueden comparar con
  # la lista, se bloquean.
  { [[ $e != *://* && $e != *//* && $e != /* && $e != *:* ]]; } ||
    bloqueo repos "no pude leer el endpoint de este gh api de escritura ($endpoint); escríbelo como repos/<dueño>/<repo>/..., sin host ni //."
  IFS=/ read -r -a p <<< "$e"
  case "${p[0]}" in
    user) case "$e" in user/repos|user/codespaces/*/publish) bloqueo repos "gh api $e crea un repo fuera de ${org:-la organización}." ;; esac ;;
    orgs|teams) bloqueo repos "el agente no escribe en la configuración de la organización ni de sus equipos (gh api $e): equipos, repos, rulesets y ajustes los maneja Leonardo." ;;
    repos)
      [ "${#p[@]}" -gt 3 ] ||
        bloqueo repos "gh api de escritura sobre el repo ($e) cambia su visibilidad, nombre o dueño, o lo borra; usa gh repo edit con sus flags permitidos."
      case "${p[3]}" in
        generate|forks|transfer) bloqueo repos "gh api $e crea o mueve un repo fuera del flujo de gh repo create." ;;
        pages|collaborators|invitations|keys|hooks|rulesets) bloqueo repos "gh api $e abre el repo a terceros o cambia sus reglas; lo hace Leonardo." ;;
        git) [ "${p[4]:-}" = refs ] && bloqueo repos "gh api $e crea, mueve o borra ramas por API; usa git push (y staging solo desde origin/main)." ;;
        # El nombre de la rama puede tener / (feat/x): se mira el final y no la posición.
        branches) case "$e" in */rename|*/protection|*/protection/*) bloqueo repos "gh api $e renombra una rama o cambia su protección; lo hace Leonardo." ;; esac ;;
      esac ;;
  esac
  return 0
}
# revisar_deploy_key <args>: gh repo deploy-key. Solo pasan list, delete y la ayuda; -R/--repo puede
# ir antes del subcomando (C3).
revisar_deploy_key() {
  local a sigue=0
  for a in "$@"; do case "$a" in --help|-h) return 0 ;; esac; done
  for a in "$@"; do
    if [ "$sigue" = 1 ]; then sigue=0; continue; fi
    case "$a" in
      -R|--repo) sigue=1 ;;
      -*) ;;
      list|delete) return 0 ;;
      *) break ;;
    esac
  done
  bloqueo repos "gh repo deploy-key solo con list o delete: add le da acceso al repo a una llave externa; lo hace Leonardo."
}
if [[ $cmd =~ $re_gh ]]; then
  # Continuación de línea (\ y salto de línea): bash la junta antes de correr el comando.
  cmd_c=${cmd//$'\\\r\n'/ }
  cmd_c=${cmd_c//$'\\\n'/ }
  plano "$cmd_c"
  cuenta "$pl" "$re_repo"; net_repo=$cnt
  cuenta "$pl" "$re_api"; net_api=$cnt
  cuenta "$pl" "$re_ext"; net_ext=$cnt
  n_repo=0 n_api=0 n_ext=0 n_create=0
  leer_conf
  # Se analizan todos los segmentos donde aparece la palabra gh, no solo los que calzan con la red
  # textual: el filtro no puede ser más estrecho que el analizador.
  partir "$(printf '%s' "$cmd_c" | sed -E 's/[0-9]*[<>]&[0-9]*-?/ /g; s/&>>?/ > /g; s/>\|/>/g')"
  for seg in "${segs[@]}"; do
    [[ $seg =~ $re_gh ]] || continue
    if ! lista=$(printf '%s' "$seg" | xargs printf '%s\n' 2>/dev/null); then
      plano "$seg"
      [[ $pl =~ $re_repo || $pl =~ $re_api || $pl =~ $re_ext ]] || continue
      bloqueo repos "no pude leer los argumentos de gh (¿comillas sin cerrar o un salto de línea dentro de comillas?); escribe el comando en una sola línea."
    fi
    toks=()
    while IFS= read -r t; do toks+=("$t"); done <<< "$lista"
    # Cierre de $(...), (...) o `...` pegado a la última palabra.
    if [ "${#toks[@]}" -gt 0 ]; then
      ult=$((${#toks[@]} - 1))
      t=${toks[ult]%\`}
      t=${t%\)}
      if [ -n "$t" ]; then toks[ult]=$t; else unset "toks[$ult]"; fi
    fi
    leer_gh || continue
    case "$gh_sub" in
      repo)
        rsub=${gh_args[0]:-}
        rargs=("${gh_args[@]:1}")
        case "$rsub" in
          create|new) n_repo=$((n_repo + 1)); n_create=$((n_create + 1)); revisar_create ${rargs[@]+"${rargs[@]}"} ;;
          edit) n_repo=$((n_repo + 1)); sin_host "gh repo edit"; revisar_edit ${rargs[@]+"${rargs[@]}"} ;;
          fork) n_repo=$((n_repo + 1)); bloqueo repos "gh repo fork crea un repo con la visibilidad del original (público si el original lo es), también dentro de la organización." ;;
          delete) n_repo=$((n_repo + 1)); bloqueo repos "gh repo delete: borrar un repo requiere el OK de Leonardo, y lo hace él." ;;
          deploy-key) n_repo=$((n_repo + 1)); revisar_deploy_key ${rargs[@]+"${rargs[@]}"} ;;
        esac ;;
      api) n_api=$((n_api + 1)); revisar_api ${gh_args[@]+"${gh_args[@]}"} ;;
      alias)
        n_ext=$((n_ext + 1))
        case "${gh_args[0]:-}" in set|import) bloqueo repos "gh alias set o import: un alias esconde cualquier comando de gh de este hook." ;; esac ;;
      extension|extensions|ext)
        n_ext=$((n_ext + 1))
        case "${gh_args[0]:-}" in install|upgrade|exec) bloqueo repos "gh extension install, upgrade o exec corren código que este hook no ve." ;; esac ;;
    esac
  done
  [ "$n_create" -le 1 ] || bloqueo repos "una sola creación de repo por comando."
  { [ "$net_repo" -le "$n_repo" ] && [ "$net_api" -le "$n_api" ] && [ "$net_ext" -le "$n_ext" ]; } ||
    bloqueo repos "hay un gh repo, gh api, gh alias o gh extension que no pude leer (dentro de comillas, bash -c o \"\$(...)\", o en el texto de un --title, un -m o un -f body=). Escribe cada uno como comando propio, y los textos con --body-file, git commit -F o gh api -F body=@archivo."
fi

# gh pr merge: solo a staging, con número de PR explícito, un merge por comando, sin --admin,
# --auto ni borrar la rama, y nunca un PR que toque (modifique, borre o renombre) una ruta de
# .claude/rutas-gobierno.txt: esos los mergea Leonardo, también a staging. Si algo no se puede
# verificar, se bloquea.
# Límites conocidos (auditorías de hooks-windows-y-gobierno). El modelo de amenaza es errores
# del agente; el control real sobre los PRs de gobierno va en el servidor (cuenta propia del
# agente y CODEOWNERS). El hook deja pasar:
# - un cd (o pushd, o un cd de un comando anterior) a otro repositorio antes del merge: consulta
#   el PR con ese número en el repositorio del directorio de la sesión, no en el del merge;
# - merges desde PowerShell u otra herramienta distinta de Bash: el hook solo corre con el
#   matcher "Bash" de .claude/settings.json;
# - gh.exe pr merge y bash -c "gh pr merge ...", que no se detectan como merge.
# Y bloquea de más, por conservador:
# - GH_REPO= o GH_HOST= escritos dentro de un --body o --subject;
# - un merge partido en varias líneas con \ o un --body de varias líneas (el mensaje es
#   engañoso); usa una sola línea y --body-file;
# - el texto "gh pr merge" dentro de un --body, que cuenta como un segundo merge.
# Detección amplia: gh pr merge con flags (y sus valores) entre gh, pr y merge, espacios de más,
# o dentro de ( ) o `...`. Un "merge" en el texto de otro subcomando (gh pr create --title
# "fix merge") no cuenta, porque entre pr y merge solo se admiten flags.
patron_merge='(^|[;&|( `])gh( +-[^ ;&|]+( +[^- ;&|][^ ;&|]*)?)* +pr( +-[^ ;&|]+( +[^- ;&|][^ ;&|]*)?)* +merge([^[:alnum:]_-]|$)'
if printf '%s\n' "$cmd" | grep -Eq "$patron_merge"; then
  bloquear() { echo "Bloqueado por protocolo: $1" >&2; exit 2; }
  minusculas() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
  # cortar <texto>: imprime el texto hasta el primer ; & | o salto de línea que esté fuera de
  # comillas y sin escapar (un --body "R&D; listo" no corta el comando).
  cortar() {
    local s=$1 out="" q="" c i=0 n=${#1}
    while [ "$i" -lt "$n" ]; do
      c=${s:i:1}
      if [ "$q" = "'" ]; then
        [ "$c" = "'" ] && q=""
      elif [ "$q" = '"' ]; then
        if [ "$c" = '\' ]; then out+=$c; i=$((i + 1)); c=${s:i:1}
        elif [ "$c" = '"' ]; then q=""; fi
      else
        case "$c" in
          "'"|'"') q=$c ;;
          '\') out+=$c; i=$((i + 1)); c=${s:i:1} ;;
          ';'|'&'|'|'|$'\n') break ;;
          '#') { [ -z "$out" ] || [[ "$out" == *[[:space:]] ]]; } && break ;;   # comentario
        esac
      fi
      out+=$c
      i=$((i + 1))
    done
    printf '%s' "$out"
  }

  estrictos=$(printf '%s\n' "$cmd" | grep -Eo '(^|[;&|( `])gh pr merge' | wc -l)
  amplios=$(printf '%s\n' "$cmd" | grep -Eo "$patron_merge" | wc -l)
  if [ $((estrictos)) -gt 1 ] || [ $((amplios)) -gt 1 ]; then
    bloquear "un merge por comando. Corre cada gh pr merge por separado."
  fi
  [ $((estrictos)) -eq 1 ] ||
    bloquear "escribe el merge como gh pr merge <n> --squash, sin nada entre gh, pr y merge."
  case "$cmd" in
    *GH_REPO=*|*GH_HOST=*) bloquear "gh pr merge con GH_REPO o GH_HOST: apunta a otro repositorio o servidor." ;;
  esac

  # Argumentos: se normalizan las redirecciones con & (2>&1, >&2, &>, >|), se corta en el primer
  # separador fuera de comillas y se separan respetando comillas con xargs (no ejecuta nada).
  # Comillas sin cerrar: no se pueden leer, se bloquea.
  resto=$(printf '%s' "${cmd#*gh pr merge}" | sed -E 's/[0-9]*[<>]&[0-9]*-?/ /g; s/&>>?/ > /g; s/>\|/>/g')
  resto=$(cortar "$resto")
  args=()
  if [ -n "${resto//[[:space:]]/}" ]; then
    lista=$(printf '%s' "$resto" | xargs -n1 printf '%s\n' 2>/dev/null) ||
      bloquear "no pude leer los argumentos de gh pr merge (¿comillas sin cerrar?)."
    while IFS= read -r a; do args+=("$a"); done <<< "$lista"
  fi

  # Flags: se saltan los valores de los que llevan uno y las redirecciones; lo que queda es el PR.
  target="" posicionales=0 salta=0
  for a in ${args[@]+"${args[@]}"}; do
    if [ "$salta" = 1 ]; then salta=0; continue; fi
    case "$a" in
      --help|-h) exit 0 ;;                # muestra la ayuda, no mergea
      [0-9]*[\<\>]*|[\<\>]*)              # redirección: >archivo, 2>err, o el operador solo
        case "$a" in *[!0-9\<\>]*) ;; *) salta=1 ;; esac ;;
      --admin|--admin=*) bloquear "--admin salta las protecciones de rama." ;;
      --auto|--auto=*) bloquear "sin --auto: GitHub mergearía después, con un estado del PR que este hook no revisó. Mergea cuando CI esté en verde." ;;
      --delete-branch|--delete-branch=*) echo "$msg_borrado" >&2; exit 2 ;;
      --repo|--repo=*) bloquear "gh pr merge en otro repositorio (-R/--repo)." ;;
      --author-email|--body|--body-file|--match-head-commit|--subject) salta=1 ;;
      --*) ;;
      -*)
        # Grupo de flags cortos: sin el =valor, las letras antes del primer flag que lleva valor
        # (A, b, F, t, R) son booleanos; lo que sigue a ese flag es su valor (-tdocs, -t7).
        grupo=${a#-}
        grupo=${grupo%%=*}
        booleanos=${grupo%%[AbFtR]*}
        case "$booleanos" in *d*) echo "$msg_borrado" >&2; exit 2 ;; esac
        if [ "$booleanos" != "$grupo" ]; then
          [ "${grupo:${#booleanos}:1}" = R ] && bloquear "gh pr merge en otro repositorio (-R/--repo)."
          # El valor va en el token siguiente si el flag con valor cierra el grupo y no hay =.
          [ "${#grupo}" -eq $((${#booleanos} + 1)) ] && [ "$a" = "${a%%=*}" ] && salta=1
        fi ;;
      *) posicionales=$((posicionales + 1)); target=$a ;;
    esac
  done
  [ "$posicionales" -gt 1 ] && bloquear "no pude identificar un único PR en gh pr merge ($posicionales argumentos sin flag)."
  case "$target" in
    ''|*[!0-9]*) bloquear "indica el número del PR: gh pr merge <n> --squash. Sin número (o con una rama o URL), el hook revisaría otro PR que el que se mergea." ;;
  esac

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
    # **/X y **/X/ con una barra interna no tienen traducción fiel a CODEOWNERS (quedaría anclada).
    case "$r" in
      '**/'*) x=${r#\*\*/}; case "${x%/}" in */*|'') bloquear "regla no soportada en .claude/rutas-gobierno.txt (barra interna): $r" ;; esac ;;
    esac
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
