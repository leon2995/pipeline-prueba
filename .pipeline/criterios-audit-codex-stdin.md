# Criterios: audit-codex-stdin

Riesgo: bajo (decisión de Leonardo). Tooling interno del pipeline: cambia cómo recibe el prompt el segundo auditor y fija los modelos y esfuerzos de cada rol. Sin datos ni integraciones nuevas.

- **C1.** `audit-codex.md` escribe el prompt completo en `.pipeline/prompt-codex-<id>.txt` y `codex exec` lo lee con `-` llevando exactamente `-m gpt-5.6-sol -c model_reasoning_effort='"high"'`. No queda `gpt-5.6-terra` ni el prompt como argumento.
- **C2.** El reintento agrega la instrucción al final del archivo con `cat >>` y vuelve a correr el mismo `codex exec`.
- **C3.** `git check-ignore .pipeline/prompt-codex-T1.txt` confirma que se ignora.
- **C4.** `settings.json` es JSON válido con `"model": "claude-opus-5-5"` y `"ultracode": true`, y permisos y hooks idénticos. `auditor.md` tiene `model: claude-opus-5-5` y `effort: high`. `test-writer.md` tiene `model: sonnet` y `effort: high`. `engineer.md` no cambia. Evidencia: una sesión `claude -p` corta en la rama confirma que arranca con Opus 5.5 y ultracode activo.
- **C5.** Un prompt sintético de más de 40.000 caracteres (prompt del auditor más un diff de relleno), pasado por entrada estándar con `-m gpt-5.6-sol -c model_reasoning_effort='"high"'`, devuelve JSON válido. Tamaño exacto y resultado en la evidencia.
- **C6.** La tabla de roles de `CLAUDE.md` muestra modelo y esfuerzo de los cinco (CTO: Opus 5.5 con ultracode; engineer: hereda de la sesión; auditor: Opus 5.5 esfuerzo alto; test-writer: Sonnet esfuerzo alto; Codex: gpt-5.6-sol esfuerzo alto), y la fila del segundo auditor dice "ChatGPT Business".
- **C7.** `LESSONS.md` contiene solo las dos lecciones generales.

Verificación posterior al PASS (fuera de los criterios del auditor): PR contra `staging` con CI en verde, merge squash a `staging` y un solo PR de `staging` a `main` con los dos cambios (hook y stdin), sin mergear.

## Plan

**Quién implementa:** el CTO (sesión principal). Todo es `.claude/`, `CLAUDE.md` o `LESSONS.md`, que el engineer no puede tocar. Flujo: auditor Claude y JEV (riesgo bajo).

1. Rama `fix/audit-codex-stdin` desde `staging` (incluye el PR #1).
2. `audit-codex.md`: paso 2 con `cat > .pipeline/prompt-codex-$ARGUMENTS.txt <<EOF` (prompt fijo, TASK, CRITERIOS, LESSONS, DIFF) y `codex exec -m gpt-5.6-sol -c model_reasoning_effort='"high"' --sandbox read-only --output-last-message .pipeline/veredicto-codex-$ARGUMENTS.json - < .pipeline/prompt-codex-$ARGUMENTS.txt`. Paso 3: reintento con `cat >>` y el mismo `codex exec`. `allowed-tools` sin cambios (los comandos empiezan con `cat` o `codex exec`).
3. `.gitignore`: `.pipeline/prompt-codex-*.txt`.
4. `.claude/settings.json`: `"model": "claude-opus-5-5"` y `"ultracode": true` (clave booleana propia; `effortLevel` no acepta `ultracode`).
5. `auditor.md`: `model: claude-opus-5-5`, `effort: high`. `test-writer.md`: `effort: high`. `engineer.md` sin cambios.
6. `CLAUDE.md`: columna "Modelo y esfuerzo" y "ChatGPT Business".
7. `LESSONS.md`: solo las dos lecciones generales.
8. Evidencia: comprobaciones de C1 a C7, sesión `claude -p` en la rama (C4) y corrida real de `/audit-codex` con un id sintético de más de 40.000 caracteres (C5).
