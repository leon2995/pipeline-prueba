# Evidencia: hook-force-push

- **Estado:** cerrado por decisión de Leonardo tras HUMAN. PR contra `staging` sin mergear.
- **Rama:** `fix/hook-force-push` (desde `staging`).
- **Implementó:** CTO (sesión principal). El engineer no puede modificar `.claude/`.
- **Intento 1:** JEV devolvió FIX (Claude y Codex en `fail`). Hallazgos en `.pipeline/veredicto-hook-force-push-intento1.json` y `.pipeline/veredicto-codex-hook-force-push-intento1.json`. Los hallazgos de código quedaron corregidos en el intento 2, cada uno con su caso en la suite; el de C5 (falta de PR) se resuelve verificándolo con el PR abierto.
- **Intento 2:** Claude y Codex en `fail` con evasiones nuevas por sintaxis de bash; JEV devolvió HUMAN por tope de reintentos (`.pipeline/veredicto-hook-force-push.json`, `.pipeline/veredicto-codex-hook-force-push.json`). La primera corrida de Codex del intento 2 falló por límite de uso de la cuenta; se repitió con el mismo prompt tras reconectar la cuenta.
- **Decisión de Leonardo:** sin intento 3. C1 pasa a declarar el modelo de amenaza (errores, no ofuscación deliberada); las evasiones conocidas se documentan al inicio de `guard-commands.sh` y en el PR.

## Protección de ramas en GitHub (verificada con `gh api repos/leon2995/pipeline-prueba/branches/<rama>/protection`)

| Rama | allow_force_pushes | allow_deletions | enforce_admins | Revisión de PR | Checks requeridos |
|---|---|---|---|---|---|
| main | false | false | true | sí | `secrets` |
| staging | false | false | true | sí | `secrets` |

## Evasiones conocidas (reproducidas contra el hook final: exit 0)

Intento 2, Claude: `git push origin "a&b" -f`, `git push "https://host/repo.git?a=1&b=2" -f`, `git push origin "a;b" -d rama`, `git push origin a\&b -f`.
Intento 2, Codex: `git>/dev/null push -f origin feat/x`, `git>/dev/null branch -d rama`, `git push -\<LF>f`, `git branch -\<LF>d rama`, `git push -{u,f}`, `git branch -{r,d} origin/rama`, `FORCE=+HEAD:refs/heads/feat/x git --config-env=remote.origin.push=FORCE push origin` y su forma separada `git --config-env remote.origin.push=FORCE push origin`.
Declaradas fuera de alcance en el plan: `V=--force; git push origin feat/x $V`, `git config remote.origin.push +refs/heads/*:refs/heads/*`, `git config alias.pf "push --force"`.
Encontradas por el CTO y los verificadores tras HUMAN (variantes de "flags en variables o sustitución"): `git push origin $'\x2df' feat/x`, `git push origin feat/x $(printf '\x2df')`.
Los 5 hallazgos reproducibles del intento 1 (`--for"ce"`, `git >/dev/null push -f`, `--m`, `git branch '-d'`, `\r` final) salen con exit 2, y awk roto con salida 0, 1 o 2 bloquea en la suite.

## Archivos

- `.claude/hooks/guard-commands.sh`: analizador awk `analizar_git` (push forzado, push a `main`, borrado de ramas) que imprime una palabra; fail-closed por salida, no por código; normalización de comillas, escapes y redirecciones. Los patrones grep de `main` y `git branch` pasaron al analizador.
- `scripts/test-hooks.sh` (nuevo): alimenta los 5 hooks con JSON y verifica el código de salida.
- `.claude/commands/audit-codex.md`: `codex exec` con `-m gpt-5.6-terra -c model_reasoning_effort='"ultra"'` (pedido de Leonardo).
- `CLAUDE.md`: fila "Segundo auditor" de la tabla de roles anota `gpt-5.6-terra` con esfuerzo `ultra` (pedido de Leonardo).
- `LESSONS.md`: 4 lecciones (comillas y salida del analizador; criterios verificables antes del PASS; separadores dentro de comillas según el modelo de amenaza; modelo de amenaza en criterios de seguridad).
- `.pipeline/criterios-hook-force-push.md`, `.pipeline/evidencia/hook-force-push.md`, `.pipeline/test-hooks-salida.txt` (salida literal de la última corrida), veredictos de los intentos 1 (`*-intento1.json`) y 2.
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

Por protocolo (CLAUDE.md, Fase 3 paso 7), el PR se abre cuando JEV devuelve `PASS`. En esta tarea JEV devolvió HUMAN y el PR se abre por decisión de Leonardo, sin intento 3. C5 no puede tener evidencia dentro del diff: se verifica con el PR abierto (base `staging`, salida de `scripts/test-hooks.sh` en la descripción, sin mergear) y el resultado queda en un comentario del PR.
