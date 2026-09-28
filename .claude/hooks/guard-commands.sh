#!/usr/bin/env bash
# Bloquea comandos peligrosos en cualquier agente. Recibe el JSON del hook por stdin.
# Salida 2 = bloquear y devolver el mensaje de stderr al agente.
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
input=$(cat)
cmd=$(printf '%s' "$input" | json_get command)
[ -z "$cmd" ] && exit 0

# Push forzado en cualquier forma y posición: --force, --force-with-lease, --force-if-includes,
# -f solo o combinado con otros flags cortos (-uf, -fu), --mirror y sus abreviaturas (fuerza
# updates), refspecs con + (git push origin +rama) y -c remote.<r>.push=+... / mirror=.
# Parte el comando por ; & | y saltos de línea; en cada segmento busca git, salta sus opciones
# globales y, si el subcomando es push, revisa todos sus argumentos. Sale 0 si hay push forzado.
# Es una barrera contra errores, no contra ofuscación: no ve aliases de git, config persistente
# ni flags escondidos en variables o sustitución de comandos (V=--force; git push origin x $V).
# No respeta comillas a propósito, para ver dentro de bash -c "git push -f". Costo aceptado: un
# git commit -m que diga literalmente "git push --force" se bloquea; usa git commit -F archivo.
is_force_push() {
  printf '%s\n' "$1" | awk '
    BEGIN { RS = "\001" }
    {
      gsub(/\\\r?\n/, " ")
      nseg = split($0, segs, /[;&|\n]/)
      for (s = 1; s <= nseg; s++) {
        ntok = split(segs[s], tok, /[ \t\r]+/)
        state = 0   # 0: busca git, 1: opciones globales de git, 2: argumentos de push
        for (i = 1; i <= ntok; i++) {
          t = tolower(tok[i])
          gsub(/^[$(`"\047]+|[)`"\047]+$/, "", t)
          if (t == "") continue
          if (state == 0) {
            if (t ~ /(^|[\/\\])git(\.exe)?$/) state = 1
          } else if (state == 1) {
            if (t ~ /^(-c|--git-dir|--work-tree|--namespace|--config-env|--attr-source|--super-prefix)$/) {
              i++; a = tolower(tok[i])
              if (a ~ /push=["\047]?\+|mirror=/) found = 1
            } else if (t !~ /^-/) {
              state = (t == "push") ? 2 : 0
            }
          } else if (t ~ /^--force/ || (t ~ /^--mi/ && index("--mirror", t) == 1) || t ~ /^-[a-z0-9]*f[a-z0-9]*$/ || t ~ /^\+./) {
            found = 1
          }
        }
      }
    }
    END { exit found ? 0 : 1 }'
}
is_force_push "$cmd"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "Bloqueado por protocolo (push forzado: --force, --force-with-lease, -f, --mirror o refspec con +). Si de verdad hace falta, pídele a Leonardo que lo ejecute él." >&2
  exit 2
elif [ "$rc" -ne 1 ] && printf '%s' "$cmd" | grep -qi 'push'; then
  # Fail-closed solo para comandos que mencionan push: si awk falla no sabemos si es forzado,
  # pero el resto de los comandos sigue funcionando para poder diagnosticar.
  echo "Bloqueado por protocolo: no pude analizar el comando para detectar push forzado (awk salió con $rc). Revisa que awk funcione." >&2
  exit 2
fi

deny_patterns=(
  'git push .* main( |$)'
  'git push .*:main( |$)'
  # Borrar ramas siempre requiere OK de Leonardo: -d (borrado "seguro") se bloquea igual que -D
  # a propósito, junto con combinados (-rd, -rD) y --delete. No lo relajes sin un PR aprobado por él.
  'git( .*)? branch( .*)? (-[a-zA-Z]*[dD][a-zA-Z]*|--delete)( |$)'
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
