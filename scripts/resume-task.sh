#!/usr/bin/env bash
# Reanuda una sesión del pipeline con la respuesta de Leonardo (Fase 2).
# Uso: bash scripts/resume-task.sh <session_id> "<respuesta de Leonardo>"
set -euo pipefail
session="${1:?session_id requerido}"
answer="${2:?respuesta requerida}"
ts=$(date +%Y%m%d-%H%M%S)
mkdir -p .pipeline/reportes

claude -p --resume "$session" "Respuesta de Leonardo: $answer
Continúa el protocolo de CLAUDE.md desde donde te quedaste. Sigue en modo no interactivo." \
  --permission-mode acceptEdits \
  --output-format json \
  --max-turns 200 \
  > ".pipeline/reportes/$ts.json"

python3 - "$ts" "$session" << 'PY'
import json, sys, pathlib
ts, session = sys.argv[1], sys.argv[2]
raw = pathlib.Path(f".pipeline/reportes/{ts}.json").read_text(encoding="utf-8")
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    data = {}
result = data.get("result", raw)
session = data.get("session_id", session)
pathlib.Path(f".pipeline/reportes/{ts}.md").write_text(result + f"\n\nSESSION={session}\n", encoding="utf-8")
print(result)
print(f"SESSION={session}")
PY
