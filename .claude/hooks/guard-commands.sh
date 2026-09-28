#!/usr/bin/env bash
# Bloquea comandos peligrosos en cualquier agente. Recibe el JSON del hook por stdin.
# Salida 2 = bloquear y devolver el mensaje de stderr al agente.
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
input=$(cat)
cmd=$(printf '%s' "$input" | json_get command)
[ -z "$cmd" ] && exit 0

deny_patterns=(
  'git push .*(--force|-f)( |$)'
  'git push .* main( |$)'
  'git push .*:main( |$)'
  'git branch -D'
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
