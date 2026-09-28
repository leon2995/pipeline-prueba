#!/usr/bin/env bash
# Punto de entrada desatendido del pipeline (Fase 2). Lo llamará Hermes, n8n o un cron.
# Corre la sesión principal (CTO) con `claude -p` siguiendo CLAUDE.md y deja el reporte en .pipeline/reportes/.
#
# Uso: bash scripts/run-task.sh "<descripción de la tarea>" [automatico|paso-a-paso]
# Salida: imprime el reporte final del CTO. La última línea es SESSION=<id> para poder reanudar.
# Si el reporte termina con "ESPERANDO OK: ...", hay que responder con scripts/resume-task.sh.
set -euo pipefail
task="${1:?descripcion de la tarea requerida}"
modo="${2:-$(cat .pipeline/modo 2>/dev/null || echo automatico)}"
ts=$(date +%Y%m%d-%H%M%S)
mkdir -p .pipeline/reportes
echo "$modo" > .pipeline/modo

prompt="Lee CLAUDE.md y síguelo al pie de la letra. Estás en modo no interactivo: no hay nadie en el chat.
Modo de trabajo: $modo.
Tarea: $task
Al terminar, o al llegar a una compuerta que requiera OK de Leonardo, escribe el reporte para Leonardo con el formato de CLAUDE.md y detente."

claude -p "$prompt" \
  --permission-mode acceptEdits \
  --output-format json \
  --max-turns 200 \
  > ".pipeline/reportes/$ts.json"

python3 - "$ts" << 'PY'
import json, sys, pathlib
ts = sys.argv[1]
raw = pathlib.Path(f".pipeline/reportes/{ts}.json").read_text(encoding="utf-8")
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    # stream-json o salida mixta: toma el ultimo objeto con "result"
    data = {}
    for line in raw.splitlines():
        try:
            obj = json.loads(line)
            if isinstance(obj, dict) and "result" in obj:
                data = obj
        except json.JSONDecodeError:
            pass
result = data.get("result", raw)
session = data.get("session_id", "")
pathlib.Path(f".pipeline/reportes/{ts}.md").write_text(result + f"\n\nSESSION={session}\n", encoding="utf-8")
print(result)
print(f"SESSION={session}")
PY
