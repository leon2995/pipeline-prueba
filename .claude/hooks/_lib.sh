#!/usr/bin/env bash
# Helper compartido: extrae campos del JSON que Claude Code manda por stdin.
# Usa jq si existe; si no, python3. Uso: field=$(printf '%s' "$input" | json_get command)
json_get() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".tool_input.${key} // .${key} // empty" 2>/dev/null
  else
    python3 -c '
import sys, json
key = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); sys.exit(0)
t = d.get("tool_input") or {}
v = t.get(key, d.get(key, ""))
if isinstance(v, bool): v = str(v).lower()
print("" if v is None else v)
' "$key" 2>/dev/null
  fi
}
