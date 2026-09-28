# Evidencia: hooks-windows-y-gobierno

- **Estado:** listo para auditoría de código.
- **Rama:** `fix/hooks-windows-y-gobierno` (desde `staging`).
- **Implementó:** CTO (sesión principal). Todo es `.claude/`, `CLAUDE.md`, `scripts/test-hooks.sh` o `SETUP.md`.
- **Riesgo:** medio. Plan auditado: vuelta 1 `fail` (2 altas, 5 medias, 1 baja), vuelta 2 `pass` (1 media, 5 bajas); todos los hallazgos incorporados al plan.
- **Modelo de amenaza:** errores del agente, no ofuscación deliberada.

## Archivos

- `.claude/hooks/protect-acceptance-tests.sh` y `.claude/hooks/only-acceptance-tests.sh`: quitan un `\r` final y convierten `\` en `/` antes del `case` (C1).
- `.claude/rutas-gobierno.txt` (nuevo): única fuente de las rutas de gobierno, con el formato documentado en el propio archivo (C3).
- `.claude/hooks/guard-commands.sh`: bloque de `gh pr merge` reescrito (C3, C4, C8) y mensaje de borrado de ramas en una sola variable (`msg_borrado`), compartido por el analizador y por `gh pr merge -d`.
- `scripts/test-hooks.sh`: casos nuevos (C2, C5, C8); `caso` acepta un motivo que debe aparecer en stderr y puede correr una copia del hook (`hooks_alt`).
- `CLAUDE.md`: regla nueva en "Siempre requieren OK explícito de Leonardo", citando `.claude/rutas-gobierno.txt` (C6).
- `SETUP.md`: "ChatGPT Business" (C7).

## Tests

- TDD: las pruebas se commitearon primero (`3bd5270`); contra los hooks sin cambiar daban `139 ok, 42 fallos`, todos en las secciones nuevas.
- `bash scripts/test-hooks.sh` con la implementación: `181 ok, 0 fallos`, exit 0. Salida completa en `.pipeline/test-hooks-salida.txt`.
- Mutación: la suite nueva contra los hooks de `staging` → `139 ok, 42 fallos`, exit 1. Los 42 están en las secciones nuevas (22 de rutas de gobierno, 6 de flags, 6 de archivo de reglas, 6 de protect y 2 de only con rutas Windows). Los casos de gobierno fallan con "salió 0": el `gh` falso respondió la consulta del hook viejo y ese hook permitió el merge, es decir, fallan por la regla y no por el `gh` falso (ejemplo: `gh pr merge 102 --squash (esperaba 2, salió 0); motivo esperado: "ruta de gobierno CLAUDE.md"; stderr: ""`).
- awk en modo `--posix` (wrapper en PATH): `181 ok, 0 fallos`.
- El caso de ruta con `\r` final falla con los hooks viejos aunque el bash de Git para Windows quite el CRLF de jq: cuando el `\r` viene dentro del valor del JSON queda uno. El recorte `${path%$'\r'}` hace falta.
- Archivo ilegible: se simula con un directorio llamado `rutas-gobierno.txt` (funciona también en Windows, donde `chmod 000` no quita la lectura).

## Evidencia con gh real (solo consultas, no mergea nada)

- `gh pr merge 1 --squash` con el hook y las reglas reales → exit 2: "el PR #1 toca la ruta de gobierno .claude/commands/audit-codex.md (regla **/.claude/ de .claude/rutas-gobierno.txt): lo mergea Leonardo, también a staging."
- `gh pr merge 2 --squash` → exit 2: "el PR #2 toca la ruta de gobierno .claude/agents/auditor.md (regla **/.claude/ ...)".
- Los dos mensajes nombran una ruta concreta del PR: solo es posible si las dos consultas reales (`gh pr view --json ...` y `gh api .../pulls/<n>/files`) funcionaron; un fallo de consulta daría otro mensaje.
- Permitido real: copia del hook con un `rutas-gobierno.txt` de una sola regla que no aplica (`nada/`) y `gh pr merge 1 --squash` → exit 0.
- Consultas reales para el PR 1: número 1, base `staging`, `changedFiles` 12, archivos devueltos 12, renombres 0.

## Decisiones de implementación

- Un merge por comando: si `gh pr merge` aparece más de una vez, se bloquea antes de consultar nada.
- Argumentos separados con `xargs` (respeta comillas, no ejecuta nada); comillas sin cerrar bloquean. Se saltan los valores de `-A`, `-b`, `-F`, `-t`, `--author-email`, `--body`, `--body-file`, `--match-head-commit` y `--subject`; `-R`/`--repo` bloquea; más de un argumento sin flag bloquea; sin número se consulta el PR de la rama actual.
- Flags: `--admin` y `--auto` bloquean; `-d`, `--delete-branch` y grupos de flags cortos con `d` (`-sd`) bloquean con el mensaje de borrado de ramas; `--disable-auto`, `--merge`, `--rebase`, `--squash`, `-s`, `-m`, `-r` pasan.
- Reglas: se leen de `$(dirname "$0")/../rutas-gobierno.txt`; archivo ausente, no regular, ilegible, sin reglas o con una regla con `*` fuera de `**/` bloquea. Se quitan `\r` y espacios; la comparación es en minúsculas (`tr`, compatible con bash 3.2 de macOS).
- Consultas: `gh pr view <n> --json number,baseRefName,changedFiles,files --jq ...` y `gh api repos/{owner}/{repo}/pulls/<n>/files --paginate --jq '... previous_filename'`. Cualquier falla, respuesta no numérica, base distinta de `staging`, PR sin archivos o lista incompleta bloquea. Se comparan las rutas nuevas y los nombres anteriores.

## Consecuencia declarada (decisión pendiente de Leonardo)

`**/LESSONS.md` es ruta de gobierno: todo PR de subtarea que agregue una lección nueva lo mergeará Leonardo. Este mismo PR lo mergea Leonardo (toca `.claude/`, `CLAUDE.md` y `scripts/test-hooks.sh`).
