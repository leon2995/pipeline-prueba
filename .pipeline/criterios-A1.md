# Criterios: A1 (hook para repos privados en la organización)

Riesgo: **alto**. El cambio decide qué repos puede crear el agente y si puede exponer código privado. En el plan Team de GitHub, el hook es la barrera principal: no hay forma de restringir a los miembros a crear solo repos privados. Va con proceso ligero, como excepción al congelamiento aprobada por Leonardo el 2026-09-29: una ronda del auditor Claude, sin Codex ni JEV, y Leonardo aprueba como code owner. Lo implementa el CTO (es ruta de gobierno), con las pruebas primero y la mutación contra `staging`.

Plan completo (aprobado): A1 (este PR, el hook), A2 (revisión de repos públicos al iniciar sesión, `/crear-repo`, gitleaks en CI, CLAUDE.md y SETUP.md) y B (instalador). La organización y el equipo salen de `.claude/pipeline.conf`: `org=finconnect-com` y `equipo=forja`.

## Criterios

- **C1. `gh repo create` y su alias `gh repo new`.** Pasan solo si se cumple todo esto:
  - hay una sola invocación de `gh repo create|new` en el comando;
  - hay un solo posicional, `<org>/<nombre>`, con `<org>` igual a la de `pipeline.conf` sin distinguir mayúsculas y `<nombre>` con letras, números, `.`, `_` o `-` (no `.` ni `..`);
  - hay un solo `--private`, sin valor;
  - hay un solo `--team <equipo>` (o `-t`, o `--team=<equipo>`) con el equipo de `pipeline.conf`, sin distinguir mayúsculas;
  - los demás flags salen de esta lista: `--add-readme`, `--disable-issues`, `--disable-wiki`, `-d/--description <v>`, `-g/--gitignore <v>`, `-l/--license <v>`.

  `gh repo create --help` pasa.

  Se bloquea:
  - la forma interactiva (sin argumentos);
  - sin dueño, con otro dueño, con host o con URL;
  - sin `--private`, con `--private=<v>`, con `--public` o con `--internal`, en cualquier forma;
  - sin `--team`, o con otro equipo;
  - `--source`, `--push`, `--remote`, `--clone`, `--template`, `--include-all-branches` y `--homepage`, sus formas cortas (incluida `-h`, que ahí es `--homepage`), los flags agrupados o con `=` pegado a una forma corta, `--` y cualquier flag desconocido;
  - `$` o backticks en el posicional o en el equipo;
  - comillas sin cerrar;
  - `GH_HOST=` o `GH_REPO=` en el segmento;
  - dos invocaciones en el mismo comando;
  - `pipeline.conf` sin `org` o sin `equipo`.
- **C2. `gh repo edit`.** Se bloquean:
  - `--visibility` y `--accept-visibility-change-consequences`, en cualquier forma y con cualquier valor;
  - `--default-branch`;
  - `--allow-forking`, salvo `--allow-forking=false`;
  - la forma interactiva, sin ningún flag.

  Pasan los demás flags (por ejemplo `--description`, `--delete-branch-on-merge`, `--enable-squash-merge`, `-h <url>`) y `--help`.
- **C3. Siempre bloqueados:** `gh repo fork`, `gh repo delete`, `gh repo deploy-key add` (también con `-R` antes del subcomando: de `deploy-key` solo pasan `list`, `delete` y la ayuda), `gh alias set|import` y `gh extension|ext|extensions install|upgrade|exec`. Pasan las lecturas: `gh repo view`, `gh repo list` (su `--visibility` es un filtro), `gh repo clone`, `gh alias list`, `gh extension list` y `gh repo deploy-key list`.
- **C4. `gh api` de escritura.**
  - **Cuándo es escritura:** el último `-X`/`--method` (en cualquier forma) no es GET, o, sin método, hay `-f`, `-F`, `--field`, `--raw-field` o `--input`. Un método ilegible (`-X "$M"`) cuenta como escritura.
  - **Normalización del endpoint:** se quitan `https://api.github.com/`, la `/` inicial y la query, y se pasa a minúsculas.
  - **Qué se bloquea:**
    - `user/repos` y `user/codespaces/*/publish`;
    - todo `orgs/...`;
    - `repos/<o>/<r>` exacto;
    - `repos/<o>/<r>/` seguido de `generate`, `forks`, `transfer`, `pages`, `collaborators`, `invitations`, `keys`, `hooks` o `rulesets`;
    - `repos/<o>/<r>/git/refs...`;
    - `repos/<o>/<r>/branches/<b>/rename` y `.../protection...`;
    - la escritura sin endpoint legible, con `$` o backticks en el endpoint, o con más de un posicional;
    - la escritura con otro esquema o puerto (`http://`, `:443`), con `//` o con una `/` de más después de normalizar;
    - `teams/...` (API antigua de equipos);
    - en `branches/`, un endpoint que termina en `/rename` o contiene `/protection`, aunque la rama tenga `/`.
  - **GraphQL:** se bloquea `gh api graphql` en cuatro casos:
    - con `mutation` en cualquier parte del comando, sin distinguir mayúsculas (así se ve también una query armada antes en una variable);
    - con `--input`;
    - con `query=@archivo`;
    - con un `query=` cuyo valor empieza con `$` o tiene backticks.
  - **Pasan:** las lecturas de cualquier endpoint (por ejemplo `gh api repos/<org>/x --jq .visibility`, `gh api 'orgs/<org>/repos?type=public'`, `gh api graphql -f query='query{...}'`) y las escrituras que ya usa el pipeline (`repos/{owner}/{repo}/issues/5/comments -f body=x`, `-X PATCH repos/{owner}/{repo}/pulls/5`).
- **C5. Red de seguridad textual.**
  - **Qué hace:** el texto se lee sin comillas, con las barras invertidas como `/` y sin las continuaciones de línea. En él se cuentan las apariciones de `gh … repo create|new|edit|fork|delete|deploy-key`, de `gh … api` y de `gh … alias|extension|ext|extensions`. Si alguna de las tres cuentas supera las invocaciones que el hook leyó, se bloquea: por ejemplo `bash -c "gh repo create <org>/x --public"` o `echo "$(gh api -X DELETE repos/o/r)"`.
  - **Qué se analiza:** todos los segmentos donde aparece la palabra `gh` (también `gh.exe` por su ruta de Windows), no solo los que calzan con la red.
  - **Costo aceptado:** ese texto dentro de un `--title`, un `-m` o un `-f body=` también se bloquea; se usan `--body-file`, `git commit -F` y `gh api -F body=@archivo`. Un `"$(gh api …)"` entre comillas también se bloquea, aunque sea una lectura. Una invocación dentro de `$(...)` sin comillas sí se lee.
  - *Ajustado después de la ronda del auditor:* las rutas de Windows, la continuación de línea y el análisis de todos los segmentos con `gh`.
- **C6. Identidad del agente (C4 de cuenta-agente), con `.claude/identidad-agente.txt`.**
  - `gh repo create|new|edit|rename|archive|unarchive|sync` cuentan como escritura y exigen la identidad del bot.
  - En `gh repo create|new|edit`, `-h` es `--homepage` y no ayuda: no salta la revisión.
  - En `git -C <dir> push`, el remoto se resuelve en `<dir>`. Si `<dir>` no existe, se bloquea.
- **C7. Rama `staging`.** Un `git push` cuyo destino sea `staging` (`staging`, `X:staging`, `X:refs/heads/staging`) solo pasa con estas dos condiciones:
  - la forma es exactamente `git push origin origin/main:staging` o `git push origin origin/main:refs/heads/staging`;
  - `origin/main` del directorio del push (o de `-C <dir>`) tiene `.github/CODEOWNERS`.

  Se bloquean también `--all`, `--branches` (y sus abreviaturas) y los refspecs con `*`, porque empujarían todas las ramas. Los pushes a `feat/*` y `fix/*` no cambian. La regla reconoce `git`, `git.exe` y `git` con ruta; C4 también, desde la ronda del auditor.
- **C8. Configuración.** `.claude/pipeline.conf` define `org=finconnect-com` y `equipo=forja`. La suite lee de ahí la organización y el equipo, y copia `pipeline.conf` junto a los hooks.
- **C9. Suite.** `bash scripts/test-hooks.sh` da 0 fallos con gawk y con mawk, y los casos anteriores siguen pasando. Una sola excepción: el caso `git -C "a b" push origin feat/x` pasa a usar un directorio que existe (C6). Con los hooks de `origin/staging`, la suite nueva falla en los casos de C1 a C7 (mutación).

## Fuera de alcance (A2 y B)

La revisión de repos públicos al iniciar sesión, `/crear-repo`, gitleaks en CI, CLAUDE.md, SETUP.md y el instalador. Tampoco entra `gh gist create`, que no crea repos.
