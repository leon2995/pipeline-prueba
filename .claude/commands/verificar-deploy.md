---
description: Valida un deploy en Railway en modo solo lectura. Uso /verificar-deploy staging | production
allowed-tools: Bash(railway status*), Bash(railway logs*), Bash(railway environment*), Bash(railway variables*), Bash(bash scripts/*), Bash(cat *), Read
---

Valida el ambiente `$ARGUMENTS` en Railway. Todo es solo lectura; no despliegues nada.

1. **Estado.** `railway environment $ARGUMENTS` y luego `railway status`. Confirma que el último deploy del servicio principal está en SUCCESS. Si sigue en BUILDING o DEPLOYING, espera 60 segundos y reintenta hasta 10 veces.
2. **Variables.** `railway variables --kv | cut -d= -f1` y compara contra `.pipeline/variables-requeridas.txt`. Reporta las faltantes por nombre. Nunca imprimas valores.
3. **Health.** Lee la URL base de `.pipeline/urls.json` (clave `$ARGUMENTS`) y corre `bash scripts/watch-deploy.sh <url> 5`. Vigila 5 minutos.
4. **Logs.** `railway logs | tail -n 200` y busca ERROR, Traceback, Unhandled, FATAL, " 5[0-9][0-9] ". Un solo error repetido cuenta como falla.
5. **Smoke.** Si existe `tests/smoke/`, córrelo contra la URL (`BASE_URL=<url> npm run smoke` o `BASE_URL=<url> uv run pytest tests/smoke -q`).
6. **Veredicto.** Escribe `OK` o `FALLA` con la evidencia de cada paso en máximo 10 líneas. Si es `FALLA`:
   - en `staging`: abre PR de revert contra `staging` y reporta HUMAN.
   - en `production`: abre PR de revert contra `main` y espera a Leonardo. No hagas nada más.
