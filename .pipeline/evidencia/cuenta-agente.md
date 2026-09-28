# Evidencia: cuenta-agente (T1)

- **Estado:** listo para auditoría de código.
- **Rama:** `feat/cuenta-agente` (desde `staging` en `813afe4`, con el PR #4).
- **Implementó:** CTO (sesión principal), pruebas e implementación, por la regla de rutas de gobierno (excepción aprobada por Leonardo y hecha regla permanente en `CLAUDE.md`).
- **Riesgo:** alto. Plan auditado en dos vueltas (las dos `fail`); Leonardo decidió y aprobó el plan final: token con `--insecure-storage` en `~/.talos-gh`, PowerShell denegada, regla permanente y orden a, b, d, e, c, f, g.
- **Modelo de amenaza:** errores del agente, no ofuscación deliberada.

## Commits

1. `51c37a1` test(cuenta-agente): pruebas primero. Contra los hooks de entonces: `263 ok, 84 fallos`, todos en las secciones nuevas (y el caso `GIT_CONFIG_NOSYSTEM=1 git push`, que cambió de permite a bloquea).
2. `b86d651` feat(cuenta-agente): implementación. Suite: `347 ok, 0 fallos`.
3. `9654ec4` ci(cuenta-agente): paso con mawk (ver C2).

## Criterios

- **C1.** `.github/CODEOWNERS` con las 9 reglas traducidas y dueño `@leon2995`. En la suite, `comparar_codeowners` pasa con el repo y con CRLF, y falla con: falta una regla, sobra una, otro dueño, dos dueños, `.claude/` anclado, vacío, ausente, `**/docs/adr/`, `**/a/CLAUDE.md` y reglas vacías. El hook también rechaza `**/X` y `**/X/` con barra interna (casos `barra-interna-dir` y `barra-interna-archivo`). El encabezado de `rutas-gobierno.txt` documenta la traducción y la diferencia de mayúsculas.
- **C2.** Job `hooks` en `.github/workflows/ci.yml`, con disparadores `pull_request` y `push` a `staging`, `main`, `feat/**` y `fix/**`. Corrida del push de `b86d651`: https://github.com/leon2995/pipeline-prueba/actions/runs/36437206116 → `hooks: success`, `347 ok, 0 fallos`. Esa corrida mostró que en `ubuntu-latest` awk es **GNU Awk 5.2.1**, no mawk como suponía el plan; por eso se agregó un paso que corre la suite con mawk si la imagen lo trae. Corrida del push de `9654ec4`: https://github.com/leon2995/pipeline-prueba/actions/runs/36437391390 → `hooks: success`, `347 ok, 0 fallos` con gawk y `347 ok, 0 fallos` con mawk (la imagen lo trae; el mensaje "se omite" no aparece en la salida).
- **C3.** `guard-commands.sh`, sección "Credenciales e identidad del agente", antes del analizador. Casos en la suite: 25 de credenciales (incluidos `grep -rn GH_TOKEN .`, `echo "$GH_TOKEN"`, `gh auth status -t`, `git credential fill`, `env` en cualquier segmento, `set`, `export`, `declare -p`), 12 de cambio de identidad, 3 de aprobación y 10 permitidos (`gh auth status`, `gh pr review --comment`, `gh pr review -r`, `gh pr merge --help`, la plantilla, `set -e`, `export FOO=1`). En vivo desde la sesión: `echo GH_TOKEN` quedó bloqueado con "Bloqueado por protocolo (credenciales): el comando nombra un token...".
- **C4.** `guard-commands.sh`, sección "Identidad de talos-bot", activa solo si existe `.claude/identidad-agente.txt` junto a los hooks. Casos sobre copias del hook con el archivo y un `gh` falso que responde `api user`: 9 escrituras bloqueadas sin identidad (commit, push, `gh pr create|merge|comment`, `gh api` con `-f`, graphql, `-X PATCH --input`, `--method DELETE`), 6 lecturas permitidas, 5 escrituras permitidas con la identidad completa (y el merge de gobierno sigue bloqueado), 5 bloqueos con identidad incompleta o de otra cuenta (y el commit, que no consulta a GitHub, pasa con el entorno completo aunque GitHub responda como otra cuenta), archivo vacío bloquea, y sin el archivo lo cotidiano pasa. Toda la suite corre sobre una copia de los hooks sin el archivo y sin las variables de identidad de quien la lanza (`env -u ...` en `caso`).
- **C5.** `.gitignore` ignora `.claude/settings.local.json`; `.claude/settings.json` deniega `PowerShell` y `Read`/`Edit`/`Write` sobre `./.claude/settings.local.json`, `**/.claude/settings.local.json` y `~/.talos-gh/**` (10 chequeos con jq); plantilla `.claude/settings.local.example.json` validada campo por campo y sin prefijos de token.
- **C6.** `CLAUDE.md`: párrafos "Cuentas de GitHub" y "Cambios en rutas de gobierno" bajo la tabla de roles; Fase 4 (PRs de `talos-bot`, gobierno aprobado y mergeado por Leonardo, `staging` → `main` con aprobación); lista de OK con el servidor; sección nueva "Credenciales" (dónde vive el token, qué procesos llegan, PowerShell denegada, identidad obligatoria con el archivo).
- **C7.** `SETUP.md`, sección "4b. Cuenta del agente (`talos-bot`) y CODEOWNERS", en el orden a, b, d, e, c, f, g: scopes (`public_repo` solo para repos públicos, `repo` para privados, `workflow`), login interactivo con `--insecure-storage` en `~/.talos-gh`, campo "Vence: AAAA-MM-DD" con recordatorio de rotar 14 días antes, verificación de las dos identidades y del helper, comandos `gh api` con `-F` y JSON de checks con `app_id` 15368, GET de verificación, rerun del CI de PRs abiertos, alternativa si `staging` no bloquea y fusión de `settings.local.json` con reinicio de la sesión.

## Tests

- `bash scripts/test-hooks.sh` en Windows (Git Bash, gawk): `347 ok, 0 fallos`. Salida completa en `.pipeline/test-hooks-salida.txt`.
- CI en Linux: `347 ok, 0 fallos` con gawk (corridas 36437206116 y 36437391390) y con mawk (36437391390).
- Mutación: la suite de la rama contra los archivos de `staging` (hooks, reglas, `settings.json`, `.gitignore`, CI, sin CODEOWNERS ni plantilla) → `259 ok, 88 fallos`, exit 1, todos en secciones nuevas: 25 de credenciales, 12 de cambio de identidad, 3 de aprobación, 2 de permitidos nuevos (`gh pr merge --help`), 16 de C4, 2 de reglas con barra interna, 2 de CODEOWNERS, 25 de configuración y 1 por el caso `GIT_CONFIG_NOSYSTEM` que pasó a bloquea.
