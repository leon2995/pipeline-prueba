# Criterios: nombre-agente

Riesgo: **bajo**. Cambia el nombre de la cuenta del agente en textos, la plantilla y las pruebas; la lógica del hook no cambia. La cuenta `talos-bot` estaba ocupada y Leonardo creó `talos-bot-leon` (paso a de `SETUP.md` 4b), con el email noreply `335185800+talos-bot-leon@users.noreply.github.com`. Toca rutas de gobierno: lo implementa el CTO (pruebas primero, mutación contra `staging`, auditor Claude y Codex) y lo aprueba y mergea Leonardo. Tiene que entrar a `staging` antes del paso e: después, un PR de gobierno abierto por `leon2995` no se puede aprobar.

- **C1.** En `CLAUDE.md`, `SETUP.md`, `.claude/settings.local.example.json`, `.claude/hooks/guard-commands.sh` y `scripts/test-hooks.sh`, cada mención de la cuenta del agente dice `talos-bot-leon`; no queda ningún `talos-bot` que no sea parte de `talos-bot-leon`, salvo la nota del paso a que pide C4 (*corrección posterior a la auditoría: los dos auditores marcaron que C1 y C4 se contradecían en la redacción; la implementación ya seguía a C4*). No cambian `~/.talos-gh`, los nombres de variables ni los identificadores de la suite (`talos_env`, `talos_git`, `talos_base`).
- **C2.** La plantilla fija `GIT_AUTHOR_NAME` y `GIT_COMMITTER_NAME` en `talos-bot-leon`, y `GIT_AUTHOR_EMAIL` y `GIT_COMMITTER_EMAIL` en `335185800+talos-bot-leon@users.noreply.github.com`. La suite lo comprueba.
- **C3.** En `guard-commands.sh` solo cambian comentarios y textos de mensajes; ninguna condición, patrón ni variable. La suite da `395 ok, 0 fallos`, en local y en CI con gawk y con mawk.
- **C4.** `SETUP.md`: el paso a dice que `talos-bot` estaba ocupado y que la cuenta es `talos-bot-leon`; el paso f dice que el email noreply ya viene en la plantilla; el paso g crea `.claude/identidad-agente.txt` con `talos-bot-leon`.
- **C5.** Los archivos históricos de `.pipeline/` (criterios, evidencia y veredictos de tareas anteriores) no cambian.

## Plan

1. Pruebas primero (commit aparte): en `scripts/test-hooks.sh`, `talos-bot` pasa a `talos-bot-leon` y la plantilla se comprueba con el email completo. Contra los archivos de `staging` fallan los casos de C4 (mensaje) y los de la plantilla.
2. Implementación: el mismo cambio en `guard-commands.sh` (comentarios y mensajes), la plantilla, `CLAUDE.md` y `SETUP.md`, más las notas de los pasos a y f.
3. Suite local y CI, mutación contra `staging`, evidencia, auditor Claude y Codex, JEV con riesgo bajo, PR contra `staging` sin mergear.
