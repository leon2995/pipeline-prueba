# Evidencia: hooks-windows-y-gobierno

- **Estado:** cerrado por decisión de Leonardo tras HUMAN en el intento 2 (auditor Claude `pass`, Codex `fail`, JEV "auditores en desacuerdo"). Sin intento 3: los hallazgos del intento 2 quedan como límites conocidos en el hook y en el PR; el control real sobre los PRs de gobierno irá en el servidor (cuenta de GitHub propia del agente y CODEOWNERS) en el siguiente PR. PR contra `staging` sin mergear.
- **Intento 2:** Claude `pass` (1 media preexistente: el hook no cubre la herramienta PowerShell; 2 bajas: continuación de línea, `gh.exe` y `bash -c`) y Codex `fail` (1 alta: `cd` a otro repo antes del merge; 1 media: `GH_REPO` dentro de `--body`). Veredictos en `.pipeline/veredicto-hooks-windows-y-gobierno.json` y `.pipeline/veredicto-codex-hooks-windows-y-gobierno.json`.
- **Intento 1:** JEV FIX. Claude `fail` (1 alta: sin número se revisaba el PR de la rama actual; 1 media: redirecciones; 1 baja) y Codex `fail` (3 altas: `--admin=true`, `-d=true`, casos Windows faltantes en `only-acceptance-tests.sh`; 1 media: separadores dentro de comillas). Veredictos en `.pipeline/veredicto-hooks-windows-y-gobierno-intento1.json` y `.pipeline/veredicto-codex-hooks-windows-y-gobierno-intento1.json`. Todos corregidos en el intento 2, cada uno con casos en la suite.
- **Rama:** `fix/hooks-windows-y-gobierno` (desde `staging`).
- **Implementó:** CTO (sesión principal). Todo es `.claude/`, `CLAUDE.md`, `scripts/test-hooks.sh` o `SETUP.md`.
- **Riesgo:** medio. Plan auditado: vuelta 1 `fail` (2 altas, 5 medias, 1 baja), vuelta 2 `pass` (1 media, 5 bajas); todos los hallazgos incorporados al plan.
- **Modelo de amenaza:** errores del agente, no ofuscación deliberada.

## Archivos

- `.claude/hooks/protect-acceptance-tests.sh` y `.claude/hooks/only-acceptance-tests.sh`: quitan un `\r` final y convierten `\` en `/` antes del `case` (C1).
- `.claude/rutas-gobierno.txt` (nuevo): única fuente de las rutas de gobierno, con el formato documentado en el propio archivo (C3).
- `.claude/hooks/guard-commands.sh`: bloque de `gh pr merge` reescrito (C3, C4, C8) y mensaje de borrado de ramas en una sola variable (`msg_borrado`), compartido por el analizador y por `gh pr merge -d`.
- `scripts/test-hooks.sh`: casos nuevos (C2, C5, C8); `caso` acepta un motivo que debe aparecer en stderr y puede correr una copia del hook (`hooks_alt`).
- `CLAUDE.md`: regla nueva en "Siempre requieren OK explícito de Leonardo", citando `.claude/rutas-gobierno.txt` (C6); la Fase 4 pasa a `gh pr merge <n> --squash`, con número explícito (intento 2).
- `SETUP.md`: "ChatGPT Business" (C7).

## Tests

- TDD: las pruebas se commitearon primero (`3bd5270`); contra los hooks sin cambiar daban `139 ok, 42 fallos`, todos en las secciones nuevas.
- Intento 1: `bash scripts/test-hooks.sh` → `181 ok, 0 fallos`; mutación contra `staging` → `139 ok, 42 fallos`.
- Intento 2: `bash scripts/test-hooks.sh` → `226 ok, 0 fallos`, exit 0. Salida completa en `.pipeline/test-hooks-salida.txt`. Casos nuevos: número explícito (sin número, `git switch x && gh pr merge --squash`, rama, URL), redirecciones (`2>&1`, `2>/dev/null`, `> log`, `>log`, `&>`, `| tail`), separadores y `#` comentario, separadores dentro de comillas en `--body`/`--subject`, formas con `=` (`--admin=true`, `--auto=true`, `--delete-branch=true`, `-d=true`, `-sd=true`), grupos cortos con valor (`-tdocs`, `-bdone`, `-t=7`, `-st asunto`, `-st 7 102`), formas de escribir el merge (`(gh pr merge ...)`, `gh pr -R x merge`, doble espacio, `GH_REPO=`), falsos positivos que deben pasar (`gh pr create --title "fix merge conflicts"`, `gh pr comment --body "please merge"`, `gh pr view --json mergeable`) y los casos Windows completos de `only-acceptance-tests.sh`.
- Mutación del intento 2: la suite contra los hooks de `staging` → `164 ok, 62 fallos`, exit 1, todos en secciones nuevas (36 de rutas de gobierno y formas del merge, 12 de flags, 6 de archivo de reglas, 6 de protect y 2 de only con rutas Windows). Los casos de gobierno fallan con "salió 0" (el hook viejo permite): fallan por la regla, no por el `gh` falso.
- awk en modo `--posix` (wrapper en PATH): `226 ok, 0 fallos`.
- El caso de ruta con `\r` final falla con los hooks viejos aunque el bash de Git para Windows quite el CRLF de jq: cuando el `\r` viene dentro del valor del JSON queda uno. El recorte `${path%$'\r'}` hace falta.
- Archivo ilegible: se simula con un directorio llamado `rutas-gobierno.txt` (funciona también en Windows, donde `chmod 000` no quita la lectura).

## Evidencia con gh real (solo consultas, no mergea nada)

- `gh pr merge 1 --squash` con el hook y las reglas reales → exit 2: "el PR #1 toca la ruta de gobierno .claude/commands/audit-codex.md (regla **/.claude/ de .claude/rutas-gobierno.txt): lo mergea Leonardo, también a staging."
- `gh pr merge 2 --squash` → exit 2: "el PR #2 toca la ruta de gobierno .claude/agents/auditor.md (regla **/.claude/ ...)".
- Los dos mensajes nombran una ruta concreta del PR: solo es posible si las dos consultas reales (`gh pr view --json ...` y `gh api .../pulls/<n>/files`) funcionaron; un fallo de consulta daría otro mensaje.
- Permitido real: copia del hook con un `rutas-gobierno.txt` de una sola regla que no aplica (`nada/`) y `gh pr merge 1 --squash` → exit 0.
- Repetida en el intento 2 con el hook final: mismos resultados.
- Consultas reales para el PR 1: número 1, base `staging`, `changedFiles` 12, archivos devueltos 12, renombres 0.

## Decisiones de implementación

- Detección: `gh pr merge` con flags (y sus valores) entre `gh`, `pr` y `merge`, espacios de más, o dentro de `( )` o comillas invertidas. Un "merge" en el texto de otro subcomando no cuenta. Si no está escrito exactamente como `gh pr merge`, se bloquea pidiendo esa forma.
- Un merge por comando: si aparece más de una vez (forma exacta o amplia), se bloquea antes de consultar nada. Límite conservador documentado: el texto `gh pr merge` dentro de un `--body` también cuenta.
- `GH_REPO=` o `GH_HOST=` en el comando bloquean (otro repositorio o servidor).
- Argumentos: se normalizan `2>&1`, `>&2`, `&>` y `>|`; se corta en el primer `;`, `&`, `|`, salto de línea o `#` de comentario fuera de comillas y sin escapar; se separan con `xargs` (respeta comillas, no ejecuta nada); comillas sin cerrar bloquean. Se descartan los tokens de redirección con su destino. Se saltan los valores de `-A`, `-b`, `-F`, `-t`, `--author-email`, `--body`, `--body-file`, `--match-head-commit` y `--subject`; `-R`/`--repo` bloquea; más de un argumento sin flag bloquea.
- Número explícito: si el objetivo no es un número (vacío, rama o URL), se bloquea. Sin número, `gh pr view` resolvería el PR de la rama actual en el momento del hook, que puede no ser el que se mergea.
- Flags: `--admin`, `--admin=*`, `--auto` y `--auto=*` bloquean; `--delete-branch[=*]` bloquea con el mensaje de borrado de ramas. En grupos cortos se quita el `=valor` y se miran solo las letras anteriores al primer flag con valor (`A`, `b`, `F`, `t`, `R`): `d` entre ellas es borrado (`-d`, `-sd`, `-d=true`), `R` como flag con valor es otro repositorio, y lo que sigue al flag con valor es su valor (`-tdocs`). `--disable-auto`, `--merge`, `--rebase`, `--squash`, `-s`, `-m`, `-r` pasan.
- Reglas: se leen de `$(dirname "$0")/../rutas-gobierno.txt`; archivo ausente, no regular, ilegible, sin reglas o con una regla con `*` fuera de `**/` bloquea. Se quitan `\r` y espacios; la comparación es en minúsculas (`tr`, compatible con bash 3.2 de macOS).
- Consultas: `gh pr view <n> --json number,baseRefName,changedFiles,files --jq ...` y `gh api repos/{owner}/{repo}/pulls/<n>/files --paginate --jq '... previous_filename'`. Cualquier falla, respuesta no numérica, base distinta de `staging`, PR sin archivos o lista incompleta bloquea. Se comparan las rutas nuevas y los nombres anteriores.

## Consecuencia declarada (decisión pendiente de Leonardo)

`**/LESSONS.md` es ruta de gobierno: todo PR de subtarea que agregue una lección nueva lo mergeará Leonardo. Este mismo PR lo mergea Leonardo (toca `.claude/`, `CLAUDE.md` y `scripts/test-hooks.sh`).
