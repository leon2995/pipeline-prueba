# Criterios: T3a (endurecer el framework antes del instalador)

Riesgo: **medio**. Solo toca rutas de gobierno: hooks, `settings.json`, la suite, `.claude/pipeline.conf`, `engineer.md` y `CLAUDE.md`, más `.gitignore`. Va con el proceso ligero, en su regla permanente: la protección con code owners está activa y la verificó Leonardo en el paso e. Eso significa una ronda del auditor Claude y la aprobación de Leonardo como code owner. Lo implementa el CTO (pruebas primero y mutación contra `staging`) y lo abre `talos-bot-leon`.

Alcance, según lo pidió Leonardo, en este orden:
1. arreglar el hook del engineer en worktrees, que es lo más urgente;
2. bloquear los comandos de Railway que escriben;
3. bloquear la lectura de la sesión de Railway de Leonardo;
4. parametrizar la suite.

**Modelo de amenaza: errores del agente, no ofuscación deliberada.** Los bloqueos frenan que el agente, por costumbre o por seguir una guía, escriba en Railway o lea la sesión de Leonardo. No cubren formas deliberadas de esconder el comando: `bash -c`, variables, `env -u X railway`, `powershell.exe -Command`, alias.

## Criterios

- **C1. El engineer en worktrees.**
  - El engineer corre con `isolation: worktree`, en `<repo>/.claude/worktrees/<n>/`. Ahí, `protect-acceptance-tests.sh` mide la ruta desde la raíz del worktree. Así permite `src/...` y `tests/unit/...`, y sigue bloqueando `tests/acceptance/`, `.claude/`, `CLAUDE.md`, `LESSONS.md`, `docs/adr/` y `.github/workflows/`. Vale con rutas Windows y POSIX.
  - Una ruta del worktree que contiene `..` se bloquea (fail-closed).
  - Fuera de un worktree, el comportamiento no cambia.
  - Casos en la suite para cada punto.
- **C2. Flujo del engineer en worktrees.**
  - `engineer.md` dice que el engineer trabaja en su worktree y que ahí hace `git switch <rama>` a la rama de la subtarea que le indica el CTO, en lugar de crear ramas o reescribir historia.
  - En la Fase 3, paso 3, `CLAUDE.md` dice que antes de delegar el CTO crea y empuja la rama, y no la deja activa en su checkout (una rama no puede estar activa en dos worktrees).
  - `.gitignore` ignora `.claude/worktrees/`.
- **C3. Railway, lista de permitidos.** El hook deja pasar solo lecturas cuando el comando del segmento es `railway` (con ruta, `.exe`, `npx @railway/cli`, `VAR=x` antes o dentro de `( )`):
  - `--help`, `-h`, `--version`, `-V` y `help` en cualquier posición;
  - `status`, `whoami`, `logs`, `list` o `ls`, `metrics` y `docs`;
  - `environment <nombre>`, `environment list|config|link`: el enlace es local y lo usa `/verificar-deploy`;
  - `service list|status|logs`, `domain list|status`, `deployment list`, `project list`, `volume list`, `variable|variables|vars|var` (listado, con la regla existente de solo nombres, extendida a todos los alias), `usage` y `usage projects`, y `api schema|search|describe`;
  - `config plan` sin `--show-values` ni `--decrypt-variables`, y `config migrate` sin `--apply` ni `--delete-files`.

  Todo lo demás se bloquea con un mensaje que dice que lo corre Leonardo. Casos en la suite:
  - **Se bloquean:** `up`, `redeploy`, `restart`, `down`, `deploy`, `add`, `init`, `link`, `unlink`, `login`, `logout`, `run`, `shell`, `ssh`, `connect`, `domain` sin subcomando, `domain delete`, `environment new` y `environment delete`, `service redeploy`, `variable set` y `variable delete`, `volume add`, `project delete`, `config apply`, `config pull`, `config plan --show-values`, `config migrate --apply`, `usage limit set`, `api` con una consulta, `mcp`, `setup agent -y`, `upgrade`, y los mismos con ruta, `.exe`, `npx @railway/cli` o `VAR=x` antes.
  - **Pasan:** las lecturas de la lista, y comandos que solo mencionan railway como texto (`grep -rn railway SETUP.md`, `cat .railway/railway.ts`, `git commit -F x`).
  - Salen del hook los patrones viejos de `railway` en `deny_patterns`, que quedan cubiertos por la lista.
- **C4. La sesión de Railway.**
  - El hook bloquea, con motivo "credenciales", los comandos que nombran `~/.railway`, `$HOME/.railway`, `${HOME}/.railway`, `/Users/<usuario>/.railway`, `.railway/config.json`, `RAILWAY_TOKEN` o `RAILWAY_API_TOKEN`.
  - `cat .railway/railway.ts` pasa.
  - `settings.json` deniega `Read`, `Edit` y `Write` sobre `~/.railway/**` y deniega las herramientas del MCP de Railway (`mcp__railway`).
  - Sale del allow la regla `Bash(railway environment*)`.
- **C5. Parametrización de la suite.** `.claude/pipeline.conf` (líneas `clave=valor`) define `dueno`, `bot` y `bot_email`. `scripts/test-hooks.sh` los lee y los usa en lugar de los valores fijos: el login del bot en los casos de identidad, el dueño en CODEOWNERS, y el nombre y el email del bot en la plantilla.
  - Falla si falta alguna clave.
  - Un chequeo prueba que `comparar_codeowners` falla si el dueño del conf no coincide con el de `CODEOWNERS`.
  - Los mensajes del hook dejan de nombrar `talos-bot-leon` fijo: dicen "la identidad del agente" o el login de `identidad-agente.txt`.
  - En este repo la suite da el mismo resultado.
- **C6. Sin regresiones.** El resto de la suite pasa, en local y en CI con gawk y con mawk. La mutación contra `staging` falla en los casos nuevos.

Verificación posterior al PASS:
- el PR queda bloqueado hasta la aprobación de Leonardo;
- después del merge, el engineer del instalador v1 escribe en su worktree sin bloqueos.
