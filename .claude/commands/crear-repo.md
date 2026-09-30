---
description: Crea el repo de un proyecto nuevo en la organización, privado y con el equipo, e instala el framework. Uso /crear-repo <nombre> [descripción]
---

Crea el repo de `$ARGUMENTS`: el primer argumento es el nombre y el resto, la descripción. Es el único camino para crear un repo (CLAUDE.md, Repos en la organización). Al final, el repo queda así:
- privado, con el equipo;
- `main` tiene el framework, entrado por el PR T0 que aprueba Leonardo;
- `staging` nace desde `main`.

**Marcadores:**
- `<org>` y `<equipo>` son `org` y `equipo` de `.claude/pipeline.conf`.
- `<nombre>` va en minúsculas, con números, `.`, `_` y `-`, y empieza con letra o número.
- `<ruta>` es la carpeta hermana del repo del framework con ese nombre, por ejemplo `C:/Users/<usuario>/proyectos/<nombre>`.
- `<scratchpad>` es la carpeta de temporales de tu sesión (la que indica el sistema), escrita con barras normales (`C:/Users/...`): en Bash, las barras invertidas se pierden. Si no hay, usa `.claude/worktrees/tmp/` del repo del framework, que git ignora.
- `<descripción>` va entre comillas simples, para que un `$` o una comilla doble no se interpreten. Si la descripción trae una comilla simple, cámbiala por una tipográfica (’).
- `<archivo>` es un archivo que escribes con Write dentro de `<scratchpad>`. Nunca va dentro de `<ruta>` (el `git add -A` lo metería en el PR), nunca con `mktemp` y nunca en `/tmp`: fuera de las carpetas de trabajo, cada lectura le pide permiso a Leonardo.
- `<n>` es el número del PR.

Escribe cada comando literal, uno por llamada, sin variables, `~` ni `$(...)`. El hook bloquea lo que no puede leer, y en `git -C` no expande variables. Cualquier comando que falle, o cuya salida no sea la esperada, es HUMAN: detente y avísale a Leonardo, sin probar otra forma.

**0. Antes de crear nada.**
- **Solo en una sesión interactiva.** En `claude -p` los permisos de estos comandos no están en la lista y el flujo no puede terminar. Si corres en `-p`, no sigas: termina con la línea `ESPERANDO OK: /crear-repo <nombre> necesita una sesión interactiva; opciones: la abro yo | cancelar`.
- **El sí de la Fase 1.** Hace falta el sí explícito de Leonardo a la propuesta de este proyecto. Para el repo de prueba de `SETUP.md` 4c.d, su pedido reemplaza ese sí.
- **Desde el repo del framework.** `test -f instalador/instalar.sh` debe salir con 0. Si no, estás en un repo instalado: pídele a Leonardo que abra la sesión en el repo del framework.
- **La fuente, limpia.** `git status --porcelain` debe salir vacío. Anota `git rev-parse --short HEAD` para el cuerpo del PR.
- **El instalador tiene que ser el nuevo (B).** Simúlalo sobre una carpeta de prueba igual a la del paso 5: con `origin` de la organización y un commit, como el README que crea el paso 1.

   ```bash
   git init <scratchpad>/sim-<nombre>
   git -C <scratchpad>/sim-<nombre> remote add origin https://github.com/<org>/<nombre>.git
   git -C <scratchpad>/sim-<nombre> commit --allow-empty -m simulacion
   bash instalador/instalar.sh <scratchpad>/sim-<nombre>
   ```

   La salida debe cumplir tres cosas:
   - tener la línea `crear .claude/identidad-agente.txt`;
   - no tener la línea `rama staging: crear`;
   - no tener ninguna línea que empiece con `nota:`.

   Si no las cumple, el instalador no es el de este flujo (por ejemplo, el v1, anterior a B, que no generaba la identidad del agente, creaba `staging` local en el commit del README y avisaba que cambiaras el dueño en `CODEOWNERS`). En ese caso es HUMAN, sin crear el repo. La suite comprueba que el instalador actual cumple las tres condiciones.

1. **Crear el repo.** Si no hay descripción, quita `-d '<descripción>'`. Si falla (por ejemplo, porque el nombre ya existe), HUMAN: no uses un repo que ya existía.

   ```bash
   gh repo create <org>/<nombre> --private --team <equipo> --add-readme -d '<descripción>'
   ```

2. **Verificar el repo.** El primero debe responder exactamente `private main true`. El segundo, una línea con `<equipo>` y su permiso; anótalo en el reporte. El tercero debe dar un SHA; un 404 es HUMAN.

   ```bash
   gh api repos/<org>/<nombre> --jq '"\(.visibility) \(.default_branch) \(.permissions.admin)"'
   gh api repos/<org>/<nombre>/teams --jq '.[] | "\(.slug) \(.permission)"'
   gh api repos/<org>/<nombre>/branches/main --jq .commit.sha
   ```

   Si no dice `private`, **detente de inmediato (HUMAN)**: avísale a Leonardo en la primera línea, con la URL del repo. El agente no puede cambiar la visibilidad; lo hace él.

3. **Verificar los rulesets de la organización.** Esperado, en este orden:
   - `deletion,non_fast_forward,pull_request,required_status_checks` dos veces;
   - `1 true` y `0 true`, una línea cada uno;
   - `secrets,hooks` dos veces.

   Cualquier otra salida (líneas de más, reglas que faltan) es HUMAN: los rulesets no están como los dejó Leonardo.

   ```bash
   gh api repos/<org>/<nombre>/rules/branches/main --jq '[.[].type] | unique | join(",")'
   gh api repos/<org>/<nombre>/rules/branches/staging --jq '[.[].type] | unique | join(",")'
   gh api repos/<org>/<nombre>/rules/branches/main --jq '.[] | select(.type == "pull_request") | .parameters | "\(.required_approving_review_count) \(.require_code_owner_review)"'
   gh api repos/<org>/<nombre>/rules/branches/staging --jq '.[] | select(.type == "pull_request") | .parameters | "\(.required_approving_review_count) \(.require_code_owner_review)"'
   gh api repos/<org>/<nombre>/rules/branches/main --jq '.[] | select(.type == "required_status_checks") | [.parameters.required_status_checks[].context] | join(",")'
   gh api repos/<org>/<nombre>/rules/branches/staging --jq '.[] | select(.type == "required_status_checks") | [.parameters.required_status_checks[].context] | join(",")'
   ```

4. **Clonar por HTTPS y crear la rama del framework.** El segundo comando debe responder `https://github.com/<org>/<nombre>.git`.

   ```bash
   git clone https://github.com/<org>/<nombre>.git <ruta>
   git -C <ruta> remote get-url --push origin
   git -C <ruta> switch -c feat/T0-framework
   ```

5. **Instalar el framework.** Primero simula sin `--modo`: la salida debe detectar `modo nuevo`, no tener ningún `conflicto` y cumplir lo del paso 0. Si no, HUMAN. Después aplica.

   ```bash
   bash instalador/instalar.sh <ruta>
   bash instalador/instalar.sh <ruta> --aplicar
   ```

6. **Lo que aprobó Leonardo va en el repo nuevo.** Con Write, dentro de `<ruta>`, escribe:
   - `docs/adr/0001-<titulo>.md` con la plantilla `docs/adr/0000-plantilla.md`: la propuesta aprobada con sus siete secciones, incluidos los criterios C1, C2...;
   - `.pipeline/modo` con el modo que eligió Leonardo;
   - `.pipeline/variables-requeridas.txt`, solo con nombres.

   Así la sesión nueva del paso 9 no repite la Fase 1.

7. **Commit, push y PR T0 a `main`.**
   - **Qué va en `<archivo>`:** escribe con Write el mensaje del commit y el cuerpo del PR, cada uno en su archivo dentro de `<scratchpad>`. El cuerpo lleva:
     - el SHA de la fuente;
     - la lista de archivos que creó el instalador;
     - la sección Agente de los pasos manuales que imprimió el instalador (`settings.local.json`), sin la línea con la ruta de la configuración de gh del bot. Esa ruta es local de Leonardo y no va a GitHub; él la tiene en su terminal.
   - **Los checks:** `gh pr checks` puede responder "no checks reported" justo después de crear el PR; espera un poco y repítelo. Si un check falla, HUMAN.
   - **El estado del PR:** con los checks en verde, el último comando debe decir `blocked`, porque el PR espera la aprobación de Leonardo. `main` todavía no tiene `CODEOWNERS`, así que GitHub no la pide como code owner: la exige el ruleset. Por eso se lo agrega como revisor.

   ```bash
   git -C <ruta> add -A
   git -C <ruta> commit -F <archivo>
   git -C <ruta> push -u origin feat/T0-framework
   gh pr create --repo <org>/<nombre> --base main --head feat/T0-framework --title "T0: framework de agentes" --body-file <archivo>
   gh pr edit <n> --repo <org>/<nombre> --add-reviewer leon2995
   gh pr checks <n> --repo <org>/<nombre> --watch --interval 30
   gh api repos/<org>/<nombre>/pulls/<n> --jq '"\(.mergeable_state) \([.requested_reviewers[].login] | join(","))"'
   ```

   Corre `gh pr checks --watch` con un timeout de Bash amplio (600000 ms). Si ese tiempo vence, no es HUMAN: un vencimiento del timeout no es un fallo del check. Repite `gh pr checks <n> --repo <org>/<nombre>` sin `--watch` hasta que todos terminen.

8. **Detente y pásale a Leonardo:**
   - el link del PR T0, para que lo apruebe y lo mergee con "Create a merge commit";
   - en `<ruta>`, copiar `.claude/settings.local.example.json` como `.claude/settings.local.json` y completar `GH_CONFIG_DIR`. Lo hace él porque el hook no te deja nombrar ese archivo.

   Railway espera al paso 9: hoy `main` solo tiene el README y `staging` no existe. Guarda la sección Railway que imprimió el instalador en el paso 5, porque se la pasas a Leonardo en el paso 9. Si ya no la tienes, repite la simulación sobre `<ruta>`.

9. **Después del merge: crear `staging` desde `main`, y Railway.**
   - **Por qué recién ahora:** antes del merge, el hook bloquea el push, porque `origin/main` todavía no tiene `CODEOWNERS`.
   - **Lo esperado:** los dos SHA deben ser iguales.
   - **Si el push falla:** no lo reintentes de otra forma. Es HUMAN, y Leonardo tiene dos salidas: crear `staging` desde la web (Branches, New branch, desde `main`), o desactivar un momento el ruleset `staging` y volver a activarlo (`SETUP.md` 4c.b).
   - **Railway:** con `staging` creada, pásale a Leonardo la sección Railway de los pasos manuales del instalador (la que guardaste en el paso 5) y él la corre en su terminal. El `package.json` del SDK de Railway entra después por PR, desde la sesión nueva.

   ```bash
   git -C <ruta> fetch origin
   git -C <ruta> push origin origin/main:refs/heads/staging
   gh api repos/<org>/<nombre>/branches/main --jq .commit.sha
   gh api repos/<org>/<nombre>/branches/staging --jq .commit.sha
   ```

10. **Reporte.** Incluye:
    - la URL del repo, la visibilidad y el equipo con su permiso;
    - las reglas de `main` y `staging`;
    - el PR T0 y los SHA de las dos ramas.

    El trabajo del proyecto sigue en una sesión nueva de Claude Code abierta en `<ruta>`. Esa sesión lee el ADR del paso 6 y arranca en la Fase 2, sin repetir la Fase 1.
