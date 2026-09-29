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
#   remote.pushDefault) y el remoto se resuelve en el directorio del hook, no en el de un cd previo.
#   El paso f exige un solo remoto, origin, en HTTPS;
# - git push (remoto-git-push): las comillas se quitan primero las dobles y después las simples, así
#   que una " dentro de un valor entre comillas simples antes del git (V='a"b' git push "x") esconde
#   el push; y las opciones largas solo se reconocen con el nombre completo (--push-opt o --rep=,
#   prefijos que git acepta, no se leen como opciones con valor);
# - C4 compara el nombre del autor y del committer, no el email (el paso f lo verifica con git var);
# - C4 revisa git commit, git push, los gh pr que escriben y gh api de escritura; gh issue, gh run
#   rerun, gh workflow run, gh label y gh release no se revisan, y gh api .../reviews con
#   event=APPROVE no se bloquea como aprobación (sale como talos-bot-leon y el servidor lo acota).
bloqueo() { echo "Bloqueado por protocolo ($1): $2" >&2; exit 2; }
# I: inicio de una invocación. F: opciones (con su valor) entre gh o git y el subcomando, o entre
# el grupo y el subcomando (gh -R o/r pr review, gh pr -R o/r review, gh --hostname x auth token).
I='(^|[;&|( `])'
F='( +-[^ ;&|]+( +[^- ;&|][^ ;&|]*)?)*'
sin_plantilla=${cmd//settings.local.example/}
if printf '%s' "$sin_plantilla" | grep -Eq 'GH_TOKEN|GITHUB_TOKEN|gh[pousr]_|github_pat_|oauth_token|settings\.local|\.talos-gh|hosts\.yml'; then
  bloqueo credenciales "el comando nombra un token o un archivo de credenciales (GH_TOKEN, GITHUB_TOKEN, oauth_token, prefijos ghp_ y similares, settings.local.json, ~/.talos-gh). Nómbralos en texto, nunca en un comando."
fi
if printf '%s\n' "$cmd" | grep -Eq "${I}gh$F +auth$F +(token|git-credential)([^[:alnum:]_-]|\$)|${I}gh$F +auth$F +status[^;&|]*( -[a-z]*t[a-z]*( |\$)| --show-token)|${I}git( +[^ ;&|]+)* +credential +(fill|approve|reject)"; then
  bloqueo credenciales "el comando imprime una credencial (gh auth token, gh auth status -t, gh auth git-credential, git credential fill)."
fi
# git credential-manager (lecciones, T2): login, logout, get, store, erase o configure tocan el
# Credential Manager de Leonardo, donde vive su credencial de git. El agente solo puede listar las
# cuentas (git credential-manager github list). También git-credential-manager y .exe, y con opciones
# globales de git antes. Límite: el texto "git credential-manager" dentro de un --title o un -m
# también cuenta; usa --body-file y -F.
gcm="${I}(git( +[^ ;&|]+)* +credential-manager|git-credential-manager)(\\.exe)?([^[:alnum:]_.-]|\$)"
if printf '%s\n' "$cmd" | grep -Eq "$gcm"; then
  while IFS= read -r seg; do
    printf '%s\n' " $seg " | grep -Eq "$gcm" || continue
    printf '%s\n' " $seg " | grep -Eq "credential-manager(\\.exe)? +github +list( [^;&|]*)?\$" ||
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
# comando que corre): vacía el entorno y con él la identidad de talos-bot-leon. Un -i del comando que env
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
  env_vacia "$seg" && bloqueo identidad "el comando vacía el entorno (env -i) y con él la identidad de talos-bot-leon."
done <<< "$(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')"
if printf '%s\n' "$cmd" | grep -Eq "GH_CONFIG_DIR|GIT_CONFIG_|${I}gh$F +auth$F +(login|logout|switch|refresh|setup-git)([^[:alnum:]_-]|\$)|${I}git( +[^;&|]*)? +(-c +[^;&|]*credential|config [^;&|]*credential)"; then
  bloqueo identidad "el comando cambiaría la cuenta de GitHub del agente (gh auth login/switch/logout/refresh/setup-git, GH_CONFIG_DIR, GIT_CONFIG_*, credential.helper). La identidad de talos-bot-leon sale de .claude/settings.local.json."
fi
if printf '%s\n' "$cmd" | grep -Eq "${I}gh$F +pr$F +review[^;&|]*( --approve| -[A-Za-z]*a[A-Za-z]*( |\$))"; then
  bloqueo aprobación "el agente nunca aprueba PRs; la aprobación de code owner es de Leonardo."
fi

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
    if printf '%s\n' "$s" | grep -Eq "${I}git$F +(commit|push)([^[:alnum:]_-]|\$)"; then
      escribe_git=1
      # El texto entre comillas no es una invocación: un "git push" dentro de un -m o un --title no
      # cuenta como push.
      if printf '%s\n' "$s" | sed -E "s/\"[^\"]*\"/ /g; s/'[^']*'/ /g" | grep -Eq "${I}git$F +push([^[:alnum:]_-]|\$)"; then
        empuja=1
        pushes+=("$seg")
      fi
    fi
    printf '%s\n' "$s" | grep -Eq "${I}gh( |\$)" || continue
    # --help o -h solo cuentan como token fuera de comillas: en un --title o --body son texto.
    printf '%s\n' "$s" | sed -E "s/\"[^\"]*\"/ /g; s/'[^']*'/ /g" | grep -Eq ' (--help|-h)( |$)' && continue
    if printf '%s\n' "$s" | grep -Eq "${I}gh$F +pr$F +(create|new|merge|review|comment|edit|close|reopen|ready)([^[:alnum:]_-]|\$)"; then
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
    falta="falta la identidad de talos-bot-leon (.claude/settings.local.json)"
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
        # Argumentos respetando comillas, con xargs (no ejecuta nada), como en gh pr merge.
        lista=$(printf '%s' "$p" | xargs -n1 printf '%s\n' 2>/dev/null) ||
          bloqueo identidad "no pude leer los argumentos de git push (¿comillas sin cerrar?); escríbelo en una sola línea, sin ; & | dentro de comillas."
        # estado 0: busca git; 1: opciones globales de git; 2: argumentos de push. El remoto es el
        # primer posicional después de push; si no hay, el valor de --repo; si no, origin (como git).
        remoto="" repo="" estado=0 sigue=""
        while IFS= read -r t; do
          t=${t#\(}                           # subshell: (git push) o (cd x && git push)
          t=${t%\)}
          if [ -n "$sigue" ]; then [ "$sigue" = repo ] && repo=$t; sigue=""; continue; fi
          if [ "$estado" = 0 ]; then
            case "$t" in git|*/git|git.exe|*/git.exe) estado=1 ;; esac
          elif [ "$estado" = 1 ]; then
            case "$t" in
              -C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix|--attr-source) sigue=valor ;;
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
              *) remoto=$t; break ;;
            esac
          fi
        done <<< "$lista"
        [ "$estado" = 2 ] || bloqueo identidad "no pude leer el git push ($p); escríbelo como git push <remoto> <rama>."
        remoto=${remoto:-$repo}
        remoto=${remoto:-origin}
        case "$remoto" in
          *://*|*@*) url=$remoto ;;
          *) url=$(git remote get-url --push "$remoto" 2>/dev/null) || url="" ;;
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
