# Evidencia: hook-force-push

- **Estado:** listo para auditoría de código.
- **Rama:** `fix/hook-force-push` (desde `staging`).
- **Implementó:** CTO (sesión principal). El engineer no puede modificar `.claude/`.

## Archivos

- `.claude/hooks/guard-commands.sh`: función `is_force_push` (awk) que reemplaza el regex de push forzado; patrón explícito de borrado de ramas con comentario; fail-closed acotado a comandos que mencionan `push`.
- `scripts/test-hooks.sh` (nuevo): alimenta los 5 hooks con JSON y verifica el código de salida.
- `.claude/commands/audit-codex.md`: `codex exec` con `-m gpt-5.6-terra -c model_reasoning_effort='"ultra"'` (pedido de Leonardo).
- `CLAUDE.md`: fila "Segundo auditor" de la tabla de roles anota `gpt-5.6-terra` con esfuerzo `ultra` (pedido de Leonardo).
- `.pipeline/criterios-hook-force-push.md`, `.pipeline/evidencia/hook-force-push.md`, `.pipeline/test-hooks-salida.txt` (salida literal de la última corrida), veredictos.
- Sin cambios: `.claude/agents/engineer.md` (`git diff origin/staging -- .claude/agents/engineer.md` vacío), `.claude/settings.json`.

## Tests

- `bash scripts/test-hooks.sh` → `65 ok, 0 fallos`, exit 0. Salida completa en `.pipeline/test-hooks-salida.txt`.
- Mayúsculas en borrado de ramas: el bucle de `deny_patterns` usa `grep -Eiq` (sin distinguir mayúsculas); además el patrón ahora nombra `[dD]` explícitamente. Casos `git branch -D rama` y `git branch -rD origin/rama` bloquean (exit 2) en la suite.
- Mismo script con awk en modo `--posix` (wrapper en PATH) → sin fallos: sin extensiones de gawk.
- Mutación: el mismo script contra el hook de `origin/staging` → `44 ok, 16 fallos`, exit 1 (antes de agregar los casos de awk roto y falsos positivos). Los tests detectan la regresión.
- Hook en vivo: `echo git push origin +rama-inexistente` desde la sesión principal quedó bloqueado con "Bloqueado por protocolo (push forzado: ...)".
- Fail-closed: con un `awk` falso que sale 2, `git push -u origin feat/x` se bloquea con "no pude analizar el comando para detectar push forzado (awk salió con 2)"; `git status` pasa.

## Resumen del diff

- Push forzado: detecta `--force*`, `-f` solo o combinado (`-uf`, `-fu`), `--mirror` y abreviaturas, refspec con `+`, `-c remote.*.push=+`, en cualquier posición, en segmentos unidos por `;`, `&&`, `|`, dentro de `bash -c "..."` y con continuación `\`.
- Borrado de ramas: `git branch` con `-D`, `-d`, combinados (`-rd`, `-rD`) y `--delete`, bloqueado a propósito.
- Falso positivo aceptado y documentado: `git commit -m "... git push --force ..."`.

## C5 (PR contra staging)

Por protocolo (CLAUDE.md, Fase 3 paso 7), el PR se abre solo cuando JEV devuelve `PASS`, es decir, después de esta auditoría. C5 no puede tener evidencia dentro del diff: se verifica con el PR abierto (base `staging`, salida de `scripts/test-hooks.sh` en la descripción) y Leonardo es quien mergea.
