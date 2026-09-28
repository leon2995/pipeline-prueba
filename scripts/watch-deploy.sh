#!/usr/bin/env bash
# Vigila un deploy: health check cada 15 s durante N minutos.
# Uso: bash scripts/watch-deploy.sh <url_base> [minutos=5] [ruta_health=/health]
set -uo pipefail
url="${1:?url base requerida}"; mins="${2:-5}"; path="${3:-/health}"
end=$((SECONDS + mins * 60)); fails=0; total=0
while [ "$SECONDS" -lt "$end" ]; do
  total=$((total + 1))
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url$path" || echo 000)
  if [ "$code" != "200" ]; then
    fails=$((fails + 1)); echo "$(date +%T) health=$code"
  fi
  if [ "$fails" -ge 3 ]; then
    echo "FALLA: $fails health checks fallidos de $total"; exit 1
  fi
  sleep 15
done
echo "OK: $total checks, $fails fallos en $mins min"
exit 0
