# Criterios: A2 (revisión de repos públicos, /crear-repo, gitleaks sin licencia, modelos, CLAUDE.md y SETUP.md)

Riesgo: **alto**. Define cómo el agente crea los repos de la organización y cómo detecta un repo público. Además, cambia el check obligatorio `secrets` y los modelos de los roles. Va con proceso ligero, como excepción al congelamiento aprobada por Leonardo el 2026-09-29: una ronda del auditor Claude, sin Codex ni JEV, y Leonardo aprueba como code owner. Lo implementa el CTO (rutas de gobierno), con las pruebas primero y la mutación contra `staging`. `SETUP.md` no es ruta de gobierno, pero entra por la misma excepción.

Plan aprobado: A1 (hook, PR #19, en `staging`), A2 (este PR) y B (instalador). Los ajustes de modelos los pidió Leonardo el 2026-09-29 y se verificaron contra Claude Code 2.1.285.

## Criterios

- **C1. Revisión de repos públicos al iniciar sesión.**
  - **El hook:** `.claude/hooks/check-public-repos.sh` corre en SessionStart, sin matcher (startup, resume, clear, compact y fork), registrado en `.claude/settings.json` con su `timeout`.
  - **Qué revisa:** los repos públicos (`gh repo list <cuenta> --visibility public`) de la organización (`org` de `pipeline.conf`) y de la cuenta del bot (`bot`).
  - **Qué imprime:** una de tres salidas, y siempre sale con 0:
    - `Repos públicos: OK` si ninguna de las dos cuentas tiene repos públicos;
    - `Repos públicos: ALERTA`, con un repo por línea (`- dueño/repo`), si alguna tiene;
    - `Repos públicos: NO SE PUDO VERIFICAR`, con la cuenta que falló, si `gh` falla o tarda más que su límite, o si falta `org` en `pipeline.conf`.
  - **Un error no es cero repos:** si una cuenta tiene repos públicos y la otra falla, sale ALERTA y además se nombra la que falló.
- **C2. Regla de CLAUDE.md para esa salida.**
  - **ALERTA:** avisar a Leonardo en la primera línea de la respuesta, con la lista; no tocar esos repos; detenerse y esperar su instrucción.
  - **NO SE PUDO VERIFICAR:** correr la verificación a mano y, si también falla, avisar igual.
  - **Sin la salida del hook en el contexto:** correrla a mano.
  - **En modo `-p`:** el aviso termina con la línea `ESPERANDO OK`.
- **C3. `/crear-repo <nombre> [descripción]`** (`.claude/commands/crear-repo.md`). Es el único camino para crear un repo, después del sí de Leonardo en la Fase 1. Pasos, con comandos literales que pasan el hook de A1:
  1. `gh repo create <org>/<nombre> --private --team <equipo> --add-readme` (con `-d` si hay descripción);
  2. verificar `private`, rama por defecto `main` y admin; si no es privado, detenerse y avisar a Leonardo;
  3. verificar que `rules/branches/main` y `rules/branches/staging` traigan `deletion`, `non_fast_forward`, `pull_request` y `required_status_checks`; si no, HUMAN;
  4. `git clone https://github.com/<org>/<nombre>.git` a la carpeta hermana del repo del framework, con ruta literal;
  5. la rama `feat/T0-framework`, el instalador con `--aplicar`, un commit con `-F`, el push y el PR a `main` con `--body-file`;
  6. detenerse: Leonardo aprueba y mergea, copia `settings.local.json` y corre los pasos de Railway;
  7. después del merge, `git push origin origin/main:refs/heads/staging` y verificar que staging y main tengan el mismo SHA.
- **C4. Job `secrets` sin licencia.**
  - **Qué corre:** `.github/workflows/ci.yml` corre gitleaks 8.30.1 (MIT) en todo el historial (`gitleaks git`, con `fetch-depth: 0`), bajando el binario de la release oficial.
  - **Verificación del binario:** el SHA-256 va fijo en el workflow (`551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb` para `gitleaks_8.30.1_linux_x64.tar.gz`, igual al `checksums.txt` de la release) y se comprueba con `sha256sum -c`.
  - **Sin la action:** no usa `gitleaks/gitleaks-action`, que pide licencia en repos de organización.
  - **Nombre y permisos:** el job se sigue llamando `secrets`, que es el check que exigen los rulesets, y declara `permissions: contents: read`.
- **C5. Modelos.**
  - **CTO:** `.claude/settings.json` tiene `"model": "claude-opus-5-5"` y `"effortLevel": "xhigh"`, y no tiene la clave `ultracode`.
  - **engineer:** `engineer.md` usa `model: claude-sonnet-5-5` y `effort: xhigh`.
  - **test-writer:** `test-writer.md` usa `model: sonnet` y `effort: high`. En Claude Code 2.1.285, el alias `sonnet` resuelve a `claude-sonnet-5-5` en first party.
  - **auditor:** `auditor.md` sigue con `model: claude-opus-5-5` y `effort: high`.
  - **Fable:** ningún agente usa un modelo Fable.
  - **CLAUDE.md:** la tabla de roles lo refleja y anota que se revisará con los intentos por subtarea y los hallazgos del auditor de las primeras 3 a 5 tareas reales. Si el engineer en Sonnet necesita más intentos, vuelve a Opus.
- **C6. CLAUDE.md, organización.**
  - Los repos de proyectos viven en la organización de `pipeline.conf`, privados y con el equipo; solo los crea el agente, con `/crear-repo`.
  - El proceso ligero, en repos de la organización, verifica las reglas con `gh api repos/<o>/<r>/rules/branches/<rama>`: `pull_request` con `require_code_owner_review: true`.
  - Credenciales dice que C4 cubre `gh repo` que escribe.
  - La plantilla de PR dice que el texto de `gh repo` o `gh api` dentro de un `--title`, `-m` o `-f body=` se bloquea: esos textos van con `--body-file`, `git commit -F` o `gh api -F body=@archivo`.
- **C7. SETUP.md, organización.** Una sección con:
  - los comandos de los dos rulesets y su verificación;
  - los ajustes de la organización: visibilidad, borrado y transferencia restringidos; forja secreto; Pages desactivado para miembros; Actions sin aprobar PRs; presupuesto con Stop usage; la app de Railway con All repositories;
  - la validación con el repo de prueba `<org>/prueba-rulesets`, que Leonardo borra al terminar;
  - la nota del token: la condición de revisar los scopes ya se cumplió (el bot entró a la organización), y al rotar el token se evalúa uno fine-grained con dueño `finconnect-com`.

  La nota de gitleaks explica el binario con el SHA fijo y cómo actualizarlo.
- **C8. Suite.** `bash scripts/test-hooks.sh` da 0 fallos con gawk y con mawk, y los casos anteriores siguen pasando. Con los archivos de `origin/staging`, la suite nueva falla en los chequeos de C1 a C7 (mutación).

## Fuera de alcance (B)

El instalador y su manifiesto. B agrega al manifiesto `check-public-repos.sh` y `crear-repo.md`, quita los pasos de protección por repo y genera `identidad-agente.txt`. Hasta que B esté en `main`, `/crear-repo` no se usa.
