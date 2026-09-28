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
    echo "Bloqueado por protocolo (borrar ramas: git branch -d/-D/--delete, git push --delete o :rama, git update-ref -d). Si de verdad hace falta, pídele a Leonardo que lo ejecute él." >&2
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
# gh pr merge: solo se permite con base staging. El merge a main lo hace Leonardo.
if printf '%s' "$cmd" | grep -Eq '(^|[;&| ])gh pr merge'; then
  if printf '%s' "$cmd" | grep -Eq -- '--admin'; then
    echo "Bloqueado: --admin salta las protecciones de rama." >&2; exit 2
  fi
  target=$(printf '%s' "$cmd" | sed -E 's/.*gh pr merge//' | tr ' ' '\n' | grep -v '^-' | grep -v '^$' | head -n1)
  base=$(gh pr view $target --json baseRefName -q .baseRefName 2>/dev/null || true)
  if [ "$base" != "staging" ]; then
    echo "Bloqueado: solo puedes mergear PRs con base staging (base detectada: ${base:-desconocida}). Usa: gh pr merge <numero> --squash. El merge a main lo hace Leonardo." >&2
    exit 2
  fi
fi
exit 0
