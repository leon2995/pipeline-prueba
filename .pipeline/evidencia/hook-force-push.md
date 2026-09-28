# Evidencia: hook-force-push

- **Estado:** listo para auditoría de código.
- **Rama:** `fix/hook-force-push` (desde `staging`).
- **Implementó:** CTO (sesión principal). El engineer no puede modificar `.claude/`.

## Archivos

- `.claude/hooks/guard-commands.sh`: función `is_force_push` (awk) que reemplaza el regex de push forzado; patrón explícito de borrado de ramas con comentario; fail-closed acotado a comandos que mencionan `push`.
- `scripts/test-hooks.sh` (nuevo): alimenta los 5 hooks con JSON y verifica el código de salida.
- `.pipeline/criterios-hook-force-push.md`, `.pipeline/evidencia/hook-force-push.md`, veredictos.
- Sin cambios: `.claude/agents/engineer.md` (`git diff origin/staging -- .claude/agents/engineer.md` vacío), `.claude/settings.json`.

## Tests

- `bash scripts/test-hooks.sh` → `64 ok, 0 fallos`, exit 0.
- Mismo script con awk en modo `--posix` (wrapper en PATH) → `64 ok, 0 fallos`: sin extensiones de gawk.
- Mutación: el mismo script contra el hook de `origin/staging` → `44 ok, 16 fallos`, exit 1 (antes de agregar los casos de awk roto y falsos positivos). Los tests detectan la regresión.
- Hook en vivo: `echo git push origin +rama-inexistente` desde la sesión principal quedó bloqueado con "Bloqueado por protocolo (push forzado: ...)".
- Fail-closed: con un `awk` falso que sale 2, `git push -u origin feat/x` se bloquea con "no pude analizar el comando para detectar push forzado (awk salió con 2)"; `git status` pasa.

## Resumen del diff

- Push forzado: detecta `--force*`, `-f` solo o combinado (`-uf`, `-fu`), `--mirror` y abreviaturas, refspec con `+`, `-c remote.*.push=+`, en cualquier posición, en segmentos unidos por `;`, `&&`, `|`, dentro de `bash -c "..."` y con continuación `\`.
- Borrado de ramas: `git branch` con `-D`, `-d`, combinados (`-rd`) y `--delete`, bloqueado a propósito.
- Falso positivo aceptado y documentado: `git commit -m "... git push --force ..."`.
