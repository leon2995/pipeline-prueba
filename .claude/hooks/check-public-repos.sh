#!/usr/bin/env bash
# SessionStart (A2): revisa si hay repos públicos en la organización de .claude/pipeline.conf (org) y
# en la cuenta del bot (bot). Lo que imprime entra al contexto de la sesión, también en claude -p, y
# CLAUDE.md (Repos en la organización) dice qué hacer con cada resultado. Siempre sale con 0: un
# SessionStart no bloquea la sesión, así que el control es detectivo. Un error nunca se confunde con
# cero repos públicos: imprime NO SE PUDO VERIFICAR con la cuenta que falló y la causa.
# REPOS_PUBLICOS_TIMEOUT: segundos por consulta a gh (20 por defecto); lo usa la suite.
set -uo pipefail
dir_conf="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
conf() { sed -n "s/^$1=//p" "$dir_conf/pipeline.conf" 2>/dev/null | tr -d '\r' | head -1; }
org=$(conf org)
bot=$(conf bot)
limite=${REPOS_PUBLICOS_TIMEOUT:-20}
case "$limite" in ''|*[!0-9]*|0) limite=20 ;; esac
tope=1000       # --limit de gh repo list: con esa cantidad, la lista puede estar incompleta
mostrar=50      # repos que se listan en la ALERTA
guia="(CLAUDE.md, Repos en la organización)"
faltan=""
[ -n "$org" ] || faltan+="org"
[ -n "$bot" ] || faltan+="${faltan:+ y }bot"
if [ -n "$faltan" ]; then
  echo "Repos públicos: NO SE PUDO VERIFICAR (falta $faltan en .claude/pipeline.conf). Corre la verificación a mano y avísale a Leonardo $guia."
  exit 0
fi
publicos="" fallidas="" incompletas=""
for cuenta in "$org" "$bot"; do
  # stdout y stderr juntos, sin archivos temporales. Si gh sale con 0, solo cuentan las líneas con forma
  # de dueño/repo (un aviso de gh en stderr no es un repo); si falla, la primera línea es la causa.
  salida=$(timeout -k 5 "$limite" gh repo list "$cuenta" --visibility public --limit "$tope" \
    --json nameWithOwner --jq '.[].nameWithOwner' 2>&1)
  rc=$?
  salida=$(printf '%s\n' "$salida" | tr -d '\r')
  if [ "$rc" -eq 0 ]; then
    salida=$(printf '%s\n' "$salida" | grep -E '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$')
    if [ -n "$salida" ]; then
      publicos+="$salida"$'\n'
      [ "$(printf '%s\n' "$salida" | wc -l)" -ge "$tope" ] && incompletas+="${incompletas:+, }$cuenta"
    fi
  else
    causa=$(printf '%s\n' "$salida" | sed '/^$/d' | head -1 | cut -c1-120)
    case "$rc" in
      124|137) causa="límite de $limite s" ;;
      127) causa="gh o timeout no está instalado" ;;
      *) causa="gh: ${causa:-salió con $rc}" ;;
    esac
    fallidas+="${fallidas:+; }$cuenta: $causa"
  fi
done
if [ -n "$publicos" ]; then
  total=$(printf '%s' "$publicos" | wc -l)
  echo "Repos públicos: ALERTA. Avísale a Leonardo en la primera línea de tu respuesta, no toques estos repos y espera su instrucción $guia:"
  printf '%s' "$publicos" | head -n "$mostrar" | sed 's/^/- /'
  [ "$total" -gt "$mostrar" ] && echo "- y $((total - mostrar)) más"
  [ -n "$incompletas" ] && echo "La lista está posiblemente incompleta ($incompletas devolvió $tope repos, el tope de la consulta)."
  [ -n "$fallidas" ] && echo "Además, no se pudo verificar: $fallidas."
elif [ -n "$fallidas" ]; then
  echo "Repos públicos: NO SE PUDO VERIFICAR ($fallidas). Corre la verificación a mano y, si también falla, avísale a Leonardo $guia."
else
  echo "Repos públicos: OK. Ni $org ni $bot tienen repos públicos."
fi
exit 0
