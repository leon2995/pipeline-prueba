#!/usr/bin/env bash
# SessionStart (A2): revisa si hay repos públicos en la organización de .claude/pipeline.conf (org) y
# en la cuenta del bot (bot). Lo que imprime entra al contexto de la sesión, también en claude -p, y
# CLAUDE.md (Repos en la organización) dice qué hacer con cada resultado. Siempre sale con 0: un
# SessionStart no bloquea la sesión, así que el control es detectivo. Un error de gh no se confunde
# con cero repos públicos: imprime NO SE PUDO VERIFICAR con la cuenta que falló.
# REPOS_PUBLICOS_TIMEOUT: segundos por consulta a gh (20 por defecto); lo usa la suite.
set -uo pipefail
dir_conf="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
conf() { sed -n "s/^$1=//p" "$dir_conf/pipeline.conf" 2>/dev/null | tr -d '\r' | head -1; }
org=$(conf org)
bot=$(conf bot)
limite=${REPOS_PUBLICOS_TIMEOUT:-20}
if [ -z "$org" ]; then
  echo "Repos públicos: NO SE PUDO VERIFICAR (falta org en .claude/pipeline.conf). Avísale a Leonardo y corre la verificación a mano (CLAUDE.md, Repos en la organización)."
  exit 0
fi
publicos="" fallidas=""
for cuenta in "$org" ${bot:+"$bot"}; do
  if salida=$(timeout "$limite" gh repo list "$cuenta" --visibility public --limit 1000 \
    --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); then
    salida=${salida//$'\r'/}
    [ -n "$salida" ] && publicos+="$salida"$'\n'
  else
    fallidas+="${fallidas:+, }$cuenta"
  fi
done
if [ -n "$bot" ]; then cuentas="Ni $org ni $bot tienen"; else cuentas="$org no tiene"; fi
if [ -n "$publicos" ]; then
  echo "Repos públicos: ALERTA. Estos repos son públicos:"
  printf '%s' "$publicos" | sed '/^$/d; s/^/- /'
  [ -n "$fallidas" ] && echo "Además, no se pudo verificar: $fallidas."
  echo "Avísale a Leonardo en la primera línea de tu respuesta, no toques esos repos y espera su instrucción (CLAUDE.md, Repos en la organización)."
elif [ -n "$fallidas" ]; then
  echo "Repos públicos: NO SE PUDO VERIFICAR ($fallidas: gh falló o tardó más de ${limite} s). Corre la verificación a mano y, si también falla, avísale a Leonardo (CLAUDE.md, Repos en la organización)."
else
  echo "Repos públicos: OK. $cuentas repos públicos."
fi
exit 0
