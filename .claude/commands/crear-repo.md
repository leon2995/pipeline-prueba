---
description: Crea el repo de un proyecto nuevo en la organización, privado y con el equipo, e instala el framework. Uso /crear-repo <nombre> [descripción]
---

Crea el repo de `$ARGUMENTS`: el primer argumento es el nombre y el resto, la descripción. Es el único camino para crear un repo (CLAUDE.md, Repos en la organización).

**Antes de empezar:**
- Hace falta el sí de Leonardo a la propuesta de la Fase 1 de este proyecto. Sin ese sí, no crees nada.
- Corre desde el repo del framework, el que tiene `instalador/`, no desde un repo instalado.
- Marcadores:
  - `<org>` y `<equipo>` son `org` y `equipo` de `.claude/pipeline.conf`.
  - `<nombre>` va en minúsculas, con números, `.`, `_` y `-`, y empieza con letra o número.
  - `<ruta>` es la carpeta hermana del repo del framework con ese nombre, por ejemplo `C:/Users/<usuario>/proyectos/<nombre>`.
  - `<n>` es el número del PR y `<archivo>` un archivo que escribes con Write.
- Escribe cada comando literal, uno por llamada, sin variables, `~` ni `$(...)`. El hook bloquea lo que no puede leer, y en `git -C` no expande variables.

1. **Crear el repo.** Si no hay descripción, quita `-d "<descripción>"`.

   ```bash
   gh repo create <org>/<nombre> --private --team <equipo> --add-readme -d "<descripción>"
   ```

2. **Verificar visibilidad, rama por defecto, permisos y equipo.** El primero debe responder `private main true`, y el segundo debe listar `<equipo>`.

   ```bash
   gh api repos/<org>/<nombre> --jq '"\(.visibility) \(.default_branch) \(.permissions.admin)"'
   gh api repos/<org>/<nombre>/teams --jq '.[].slug'
   ```

   Si no dice `private`, **detente de inmediato (HUMAN)**: avísale a Leonardo en la primera línea, con la URL del repo. El agente no puede cambiar la visibilidad; lo hace él. También es HUMAN si la rama por defecto no es `main` o si falta `<equipo>`.

3. **Verificar los rulesets de la organización.** Los dos primeros deben listar `deletion`, `non_fast_forward`, `pull_request` y `required_status_checks`; el de `staging` funciona aunque la rama todavía no exista. El tercero debe responder `1 true` (una aprobación y code owners).

   ```bash
   gh api repos/<org>/<nombre>/rules/branches/main --jq '[.[].type] | unique | join(",")'
   gh api repos/<org>/<nombre>/rules/branches/staging --jq '[.[].type] | unique | join(",")'
   gh api repos/<org>/<nombre>/rules/branches/main --jq '.[] | select(.type == "pull_request") | .parameters | "\(.required_approving_review_count) \(.require_code_owner_review)"'
   ```

   Si falta alguna regla, los rulesets no están activos: HUMAN, sin seguir.

4. **Clonar por HTTPS y crear la rama del framework.** El segundo comando debe responder `https://github.com/<org>/<nombre>.git`.

   ```bash
   git clone https://github.com/<org>/<nombre>.git <ruta>
   git -C <ruta> remote get-url --push origin
   git -C <ruta> switch -c feat/T0-framework
   ```

5. **Instalar el framework.** Primero simula y después aplica. La salida debe decir `modo nuevo` y no tener ningún `conflicto`; si no, HUMAN.

   ```bash
   bash instalador/instalar.sh <ruta> --modo nuevo
   bash instalador/instalar.sh <ruta> --aplicar --modo nuevo
   ```

6. **Commit, push y PR a `main`.**
   - Escribe con Write el mensaje del commit y el cuerpo del PR. El cuerpo lleva qué se instaló, la salida del instalador y los pasos de Leonardo.
   - Con los checks en verde, el último comando debe decir `blocked`: el PR espera la aprobación de Leonardo.
   - `main` todavía no tiene `CODEOWNERS`, así que GitHub no pide code owner: lo que exige la aprobación es el ruleset.

   ```bash
   git -C <ruta> add -A
   git -C <ruta> commit -F <archivo>
   git -C <ruta> push -u origin feat/T0-framework
   gh pr create --repo <org>/<nombre> --base main --head feat/T0-framework --title "T0: framework de agentes" --body-file <archivo>
   gh pr checks <n> --repo <org>/<nombre> --watch
   gh api repos/<org>/<nombre>/pulls/<n> --jq '"\(.mergeable_state) \([.requested_reviewers[].login] | join(","))"'
   ```

7. **Detente y pásale a Leonardo:**
   - el link del PR, para que lo apruebe y lo mergee con "Create a merge commit";
   - en `<ruta>`, copiar `.claude/settings.local.example.json` como `.claude/settings.local.json` y completar `GH_CONFIG_DIR`. Lo hace él porque el hook no te deja nombrar ese archivo;
   - los pasos de Railway que imprimió el instalador.

   En modo `-p`, termina con la línea `ESPERANDO OK: merge del PR <n> de <org>/<nombre> a main, y settings.local.json en <ruta>`.

8. **Después del merge, crear `staging` desde `main`.** Antes del merge el hook bloquea el push, porque `origin/main` todavía no tiene `CODEOWNERS`. Los dos SHA deben ser iguales. Si el push falla, no lo reintentes de otra forma: HUMAN.

   ```bash
   git -C <ruta> fetch origin
   git -C <ruta> push origin origin/main:refs/heads/staging
   gh api repos/<org>/<nombre>/branches/main --jq .commit.sha
   gh api repos/<org>/<nombre>/branches/staging --jq .commit.sha
   ```

9. **Reporte.** URL del repo, visibilidad, reglas de `main` y `staging`, el PR y los SHA de las dos ramas. El trabajo del proyecto sigue en una sesión nueva de Claude Code abierta en `<ruta>`.
