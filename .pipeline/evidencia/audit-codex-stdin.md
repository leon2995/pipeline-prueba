# Evidencia: audit-codex-stdin

- **Estado:** listo para auditoría de código.
- **Rama:** `fix/audit-codex-stdin` (desde `staging`, que ya incluye el PR #1).
- **Implementó:** CTO (sesión principal). Todo es `.claude/`, `CLAUDE.md` o `LESSONS.md`.
- **Riesgo:** bajo (decisión de Leonardo). Flujo: auditor Claude y JEV.

## Archivos

- `.claude/commands/audit-codex.md`: paso 2 arma el prompt con `cat > .pipeline/prompt-codex-$ARGUMENTS.txt <<EOF` y lo pasa a `codex exec -m gpt-5.6-sol -c model_reasoning_effort='"high"' ... - < archivo`; paso 3 reintenta con `cat >>`. La descripción del frontmatter dice "ChatGPT Business" en lugar de "ChatGPT Pro", igual que la tabla de roles. `allowed-tools` sin cambios.
- `.gitignore`: `.pipeline/prompt-codex-*.txt`.
- `.claude/settings.json`: `"model": "claude-opus-5-5"` y `"ultracode": true`.
- `.claude/agents/auditor.md`: `model: claude-opus-5-5`, `effort: high`.
- `.claude/agents/test-writer.md`: `effort: high` (sigue en `sonnet`).
- `CLAUDE.md`: columna "Modelo y esfuerzo" y "ChatGPT Business".
- `LESSONS.md`: solo las dos lecciones generales.
- Sin cambios: `.claude/agents/engineer.md`.

## Por qué `"ultracode": true` y no `effortLevel`

Verificado en el binario instalado (Claude Code 2.1.283) y en la documentación oficial: `effortLevel` solo acepta `low`, `medium`, `high`, `xhigh` y descarta en silencio otros valores; ultracode es una clave booleana propia (`settings-reference.md`: "Scope: Any file", "takes precedence over `effortLevel`"). El frontmatter de subagentes acepta `effort` con `low`, `medium`, `high`, `xhigh`, `max` o un entero; `ultracode` ahí es inválido. El engineer, sin `effort`, hereda el esfuerzo de la sesión.

## Comprobaciones

Estáticas (script de verificación, todas OK):
- C1: heredoc con `cat >` hacia `.pipeline/prompt-codex-$ARGUMENTS.txt` con las 5 secciones (prompt fijo, TASK, CRITERIOS, LESSONS, DIFF); el `codex exec` exacto con `-` aparece una vez; no queda `gpt-5.6-terra`, `ultra` ni `"$(cat` como argumento.
- C2: bloque `cat >> .pipeline/prompt-codex-$ARGUMENTS.txt <<'EOF'` con "Responde únicamente con el JSON, sin markdown" y la instrucción de correr el mismo `codex exec` del paso 2.
- C3: `git check-ignore -v .pipeline/prompt-codex-T1.txt` → `.gitignore:8:.pipeline/prompt-codex-*.txt`.
- C4: `settings.json` es JSON válido; solo agrega `model` y `ultracode`; `permissions` y `hooks` idénticos a `staging` (comparados como objetos). Frontmatter de `auditor.md` (`claude-opus-5-5`, `high`) y `test-writer.md` (`sonnet`, `high`); `git diff --quiet staging -- .claude/agents/engineer.md` sin cambios.
- C6: columna "Modelo y esfuerzo" con los cinco roles y "Codex CLI con ChatGPT Business"; no queda "ChatGPT Pro".
- C7: `LESSONS.md` con 2 lecciones (criterios verificables antes del PASS; modelo de amenaza), ninguna de filtros de shell.

C4 en ejecución (sesión nueva `claude -p --output-format json` en la rama, sin herramientas):
- Con los settings del proyecto: `MODELO=claude-opus-5-5 ULTRACODE=ON`; `modelUsage`: `claude-opus-5-5`.
- Control con `--setting-sources user` (sin settings del proyecto): `MODELO=claude-opus-5-5 ULTRACODE=OFF`. El ultracode activo viene del `settings.json` del repo. El modelo coincide en ambos casos porque Opus 5.5 también es el predeterminado; el `settings.json` lo fija explícitamente.
- `CLAUDE_CODE_EFFORT_LEVEL` sin definir en el entorno.

C5 (corrida real con los comandos exactos del nuevo `audit-codex.md`, id `sintetico`):
- Prompt `.pipeline/prompt-codex-sintetico.txt` armado con el heredoc: **72.368 caracteres** (74.199 bytes), prompt del auditor más un diff de relleno de 900 líneas. Git lo ignora (`!!`).
- `codex exec -m gpt-5.6-sol -c model_reasoning_effort='"high"' --sandbox read-only --output-last-message .pipeline/veredicto-codex-sintetico.json - < .pipeline/prompt-codex-sintetico.txt` → exit 0; el log de Codex dice `model: gpt-5.6-sol` y `reasoning effort: high`.
- Resultado, JSON válido: `{"task":"sintetico","mode":"code","verdict":"pass","findings":[],"tests_reviewed":true,"new_lesson":null}`.
- Los archivos sintéticos se movieron fuera del repo; no forman parte del diff.

Regresión: `bash scripts/test-hooks.sh` → `112 ok, 0 fallos`.
