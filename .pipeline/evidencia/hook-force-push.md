# Evidencia: hook-force-push

- **Estado:** intento 2, listo para auditoría de código.
- **Rama:** `fix/hook-force-push` (desde `staging`).
- **Implementó:** CTO (sesión principal). El engineer no puede modificar `.claude/`.
- **Intento 1:** JEV devolvió FIX (Claude y Codex en `fail`). Hallazgos en `.pipeline/veredicto-hook-force-push-intento1.json` y `.pipeline/veredicto-codex-hook-force-push-intento1.json`.

## Archivos

- `.claude/hooks/guard-commands.sh`: analizador awk `analizar_git` (push forzado, push a `main`, borrado de ramas) que imprime una palabra; fail-closed por salida, no por código; normalización de comillas, escapes y redirecciones. Los patrones grep de `main` y `git branch` pasaron al analizador.
- `scripts/test-hooks.sh` (nuevo): alimenta los 5 hooks con JSON y verifica el código de salida.
- `.claude/commands/audit-codex.md`: `codex exec` con `-m gpt-5.6-terra -c model_reasoning_effort='"ultra"'` (pedido de Leonardo).
- `CLAUDE.md`: fila "Segundo auditor" de la tabla de roles anota `gpt-5.6-terra` con esfuerzo `ultra` (pedido de Leonardo).
- `LESSONS.md`: lección del intento 1 (comillas a mitad de palabra y salida del analizador).
- `.pipeline/criterios-hook-force-push.md`, `.pipeline/evidencia/hook-force-push.md`, `.pipeline/test-hooks-salida.txt` (salida literal de la última corrida), veredictos del intento 1.
- Sin cambios: `.claude/agents/engineer.md` (`git diff origin/staging -- .claude/agents/engineer.md` vacío), `.claude/settings.json`.

## Tests

- `bash scripts/test-hooks.sh` → `112 ok, 0 fallos`, exit 0. Salida completa en `.pipeline/test-hooks-salida.txt`.
- Cada hallazgo del intento 1 tiene su caso bloqueado: `git push origin --for"ce" feature-x`, `-"f"`, `--forc'e'`, `p\ush`, `git >/dev/null push -f`, `git 2>&1 push -f`, `--m`, `--forc`, `git branch '-d'`, `"-D"`, `-\D`, `\r` final, awk roto con salida 0, 1 y 2.
- Mismo script con awk en modo `--posix` (wrapper en PATH) → `112 ok, 0 fallos`: sin extensiones de gawk.
- Mutación: el mismo script contra el hook de `origin/staging` → `64 ok, 48 fallos`, exit 1. Los tests detectan la regresión.
- Hook en vivo desde la sesión principal: `echo git push origin --for"ce" rama-inexistente` quedó bloqueado con "Bloqueado por protocolo (push forzado: ...)".

## Resumen del diff

- Push forzado: `--force*` y prefijos desde `--f`, `-f` solo o combinado, `--mirror` y prefijos desde `--m`, refspec con `+`, `-c`/`GIT_CONFIG_*` con `push=+` o `mirror`; en cualquier posición, con comillas o `\` en medio de la palabra, con redirecciones, en segmentos unidos por `;`, `&&`, `|`, dentro de `bash -c "..."` y con continuación `\`.
- Push a `main`: `main`, `'main'`, `HEAD:main`, `HEAD:refs/heads/main`.
- Borrado de ramas: `git branch` con `-D`, `-d`, combinados, `--delete` y prefijos, con o sin comillas; `git push --delete`, `-d` y `:rama`; `git update-ref -d`. Bloqueado a propósito.
- Falso positivo aceptado y documentado: `git commit -m "... git push --force ..."`.

## C5 (PR contra staging)

Por protocolo (CLAUDE.md, Fase 3 paso 7), el PR se abre solo cuando JEV devuelve `PASS`, es decir, después de esta auditoría. C5 no puede tener evidencia dentro del diff: se verifica con el PR abierto (base `staging`, salida de `scripts/test-hooks.sh` en la descripción) y Leonardo es quien mergea.
