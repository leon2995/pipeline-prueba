# Evidencia: T3a (endurecer el framework antes del instalador)

- **Estado:** auditado. Proceso ligero: una sola ronda del auditor Claude, sin Codex ni JEV.
  - **Veredicto:** `fail`, con 1 alta, 2 medias y 3 bajas (`.pipeline/veredicto-T3a.json`).
  - **Todo corregido después de la ronda**, sin volver a auditar porque el proceso ligero es de una ronda. Lo revisa Leonardo como code owner.
  - **Alta (regresión frente a `staging`):** `railway_args` no veía railway después de palabras clave de shell ni de envoltorios. `for ...; do railway up; done`, `if ! railway up` o `timeout 600 railway up` pasaban. Ahora se saltan `if`, `then`, `else`, `elif`, `do`, `while`, `until`, `!` y `{`, y los envoltorios `time`, `timeout`, `xargs`, `watch`, `nice`, `ionice`, `stdbuf` y `winpty`, con sus opciones y su número o duración.
  - **Media, ayuda del comando hijo:** un `-h` del comando hijo contaba como ayuda (`railway ssh -- df -h`). Ahora la ayuda cuenta antes de `--` y dentro de las dos primeras palabras. En `run`, `ssh`, `shell`, `connect`, `dev` y `code` cuenta solo justo después del subcomando.
  - **Media, barras invertidas:** una ruta con barras invertidas (`C:\Users\x\.railway\config.json`) no se detectaba. Ahora el chequeo corre sobre una copia con `\` pasadas a `/`, y suma `/home/<u>/.railway`.
  - **Bajas:**
    - `environment` pasa a lista explícita (`link`, `list`, `ls`, `config`, `show`, `info`) y `/verificar-deploy` usa `railway environment link <ambiente>`;
    - `USERPROFILE` solo cuenta si `.railway` va justo después;
    - sale la alternativa redundante de `protect-acceptance-tests.sh`.
  - **Casos nuevos en la suite:** 16 que se bloquean, 6 que pasan y 5 de la sesión. La prueba rápida de las correcciones dio 34 de 34.
  - **Pendiente de lecciones:** el `new_lesson` de la ronda va a `.pipeline/lecciones-pendientes.md` con el PR de lecciones #14, para no chocar con ese archivo.
- **Rama:** `feat/T3a-endurecer`, desde `staging` en `ba8ed7c` (con el #13).
- **Implementó:** el CTO, pruebas e implementación (rutas de gobierno). Commits como `talos-bot-leon`.
- **Riesgo:** medio.
- **Protección:** Leonardo verificó code owners en el paso e. Con la cuenta del bot, las dos ramas dan `protected: true`.

## Commits

1. `e2ca35a` test(T3a). Contiene:
   - casos de worktrees para el hook del engineer;
   - casos de Railway: 50 lecturas que pasan, 57 escrituras que se bloquean y 2 de solo nombres;
   - 11 casos de la sesión de Railway;
   - chequeos de `settings.json`, `.gitignore`, `pipeline.conf`, `engineer.md` y `CLAUDE.md`;
   - la suite parametrizada con `.claude/pipeline.conf`, que va incluido.
2. `8755e1b` feat(T3a). Implementación: los dos hooks, `settings.json`, `.gitignore`, `engineer.md` y `CLAUDE.md`.

## Criterios

- **C1.** `protect-acceptance-tests.sh` quita `<...>/.claude/worktrees/<n>/` antes de clasificar la ruta. Si la ruta tiene `/..`, no la reinterpreta y queda bloqueada por `*/.claude/*`. Casos:
  - 4 que pasan: `src` y `tests/unit`, en Windows y POSIX, más `instalador/`;
  - 10 que se bloquean: `tests/acceptance`, `.claude/hooks`, `.claude/settings.json`, `CLAUDE.md`, `LESSONS.md`, `docs/adr`, `.github/workflows`, dos rutas con `..` y la carpeta de worktrees sola.
- **C2.** `engineer.md`, regla 0: `git switch <rama>`, sin ramas nuevas ni reescritura, y BLOCKED si falla. `CLAUDE.md`, Fase 3, paso 3: el CTO crea y empuja la rama y no la deja activa en su checkout. `.gitignore`: `.claude/worktrees/`.
- **C3.** `guard-commands.sh` define `railway_args`, que detecta la invocación por la primera palabra del segmento, y `railway_lectura`, la lista de permitidos. Salen los 6 patrones viejos de `deny_patterns`. La regla de solo nombres cubre `variable`, `variables`, `vars` y `var`, salvo con `--help`.
- **C4.** La sesión de Railway:
  - un bloqueo de credenciales para `RAILWAY_(API_)?TOKEN`, `~/.railway`, `$HOME/.railway`, `${HOME}/.railway`, `/Users/<u>/.railway`, `.railway/config.json` y `%USERPROFILE%` con `\.railway`;
  - en `settings.json`, deny de `Read`, `Edit` y `Write` sobre `~/.railway/**`, deny de `mcp__railway`, y sale el allow `Bash(railway environment*)`.
- **C5.** `.claude/pipeline.conf` tiene `dueno`, `bot` y `bot_email`. La suite los lee con `conf()`; ya no quedan `talos-bot-leon` ni `335185800` fijos, y `leon2995` solo aparece como texto de comandos de prueba. Chequeos: las tres claves, el email noreply del bot, y CODEOWNERS con otro dueño, que debe fallar. Los mensajes del hook dicen "la identidad del agente" o el login de `identidad-agente.txt`.
- **C6.** Ver Tests.

## Tests

- **Prueba rápida sobre copias de los hooks:** 54 de 54.
- **Suite:** `636 ok, 0 fallos` (Git Bash, gawk) después de las correcciones de la ronda; antes eran `608 ok`. Salida completa en `.pipeline/test-hooks-salida.txt`.
- **Mutación contra `staging`:** la suite de la rama, con su `pipeline.conf`, contra los hooks, las reglas, los settings, el CI, la plantilla, `CLAUDE.md`, los prompts de auditor y `engineer.md` de `staging`. Resultado: `531 ok, 77 fallos`, exit 1, todos en áreas nuevas:
  - 55 de Railway: escrituras que `staging` permite, `--help` y `echo railway up`, que `staging` bloqueaba de más, y el motivo "Railway";
  - 9 de la sesión de Railway;
  - 4 de worktrees: `staging` bloquea todo;
  - 6 de configuración: denegaciones, el allow de `railway environment` y `.gitignore`;
  - 3 de protocolo: `engineer.md`, `CLAUDE.md` y un artefacto, porque el script de mutación no copia `SETUP.md`.
- **En vivo:** con el hook nuevo en la copia de trabajo, mi propio `sed` que nombraba la carpeta de sesión de Railway quedó bloqueado con el motivo de credenciales.
