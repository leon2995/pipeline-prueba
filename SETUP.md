# Setup del pipeline (una sola vez)

Orden recomendado. Tiempo total: 30 a 45 minutos.

## 1. Herramientas en la máquina donde corre Claude Code

```bash
# Claude Code (ya lo tienes). Verifica:
claude --version

# GitHub CLI
brew install gh        # o: sudo apt install gh
gh auth login          # elige GitHub.com, HTTPS, login por navegador

# Railway CLI
npm i -g @railway/cli  # o: brew install railway
railway login
railway setup agent -y # instala skills y MCP de Railway para Claude Code y Codex

# Codex CLI (segundo auditor, usa tu ChatGPT Business)
npm i -g @openai/codex
codex login            # elige "Sign in with ChatGPT"

# jq (si falta, los hooks usan python3; scripts/test-hooks.sh lo exige)
brew install jq        # o: sudo apt install jq
```

## 2. Copia estos archivos al repo

Copia todo el contenido de esta carpeta a la raíz de tu proyecto (incluyendo `.claude/`, `.github/`, `.pipeline/`). Luego:

```bash
chmod +x .claude/hooks/*.sh scripts/*.sh
git checkout -b staging && git push -u origin staging
git checkout main
```

Edita `.pipeline/urls.json` con tus URLs reales y `.pipeline/variables-requeridas.txt` con los nombres de tus variables.

## 3. Railway

1. En el proyecto de Railway, conecta el repo de GitHub al servicio principal.
2. Crea el ambiente `staging` (duplicando `production` sirve).
3. En cada ambiente, configura la rama que dispara el deploy: `staging` → rama `staging`, `production` → rama `main`.
4. Confirma que el servicio expone `/health` con respuesta 200 (o cambia `healthcheckPath` en `railway.json`).
5. Enlaza el repo local: `railway link` y elige el proyecto. El token de tu `railway login` se usa solo para lectura; el deploy lo hace GitHub.

## 4. GitHub

Esta es la protección inicial, mientras el agente todavía usa tu cuenta. Al conectar la cuenta del agente (4b, paso e) cambian las aprobaciones de `main`, los code owners y los checks obligatorios.

1. Settings → Branches → Add rule para `main`:
   - Require a pull request before merging, con 0 aprobaciones requeridas por ahora. GitHub no deja aprobar tu propio PR y, hasta el paso 4b.f, los PR los abre tu cuenta; tu "aprobación" es mergear tú mismo desde la web o la app.
   - Require status checks to pass: marca `secrets` ahora y `node` o `python` en cuanto aparezcan (GitHub solo los lista después de que corren una vez).
   - Do not allow bypassing the above settings.
2. Misma regla para `staging`.
3. En repos privados de cuentas personales gratuitas, la protección de ramas no está disponible (requiere GitHub Pro, Team o una organización con plan). Para el repo de práctica usa uno público.

## 4b. Cuenta del agente (`talos-bot-leon`) y CODEOWNERS

El agente trabaja con su propia cuenta de GitHub para que el servidor pueda exigir tu aprobación como code owner en los PRs de gobierno (`.github/CODEOWNERS`, derivado de `.claude/rutas-gobierno.txt`). Los pasos van en este orden: **a, b, d, e, c, f, g**. Corre los comandos en tu terminal, no a través del agente: el hook bloquea los que nombran tokens, `GH_CONFIG_DIR` o `~/.talos-gh`. La excepción es la verificación del paso f, que va con `!` dentro de la sesión.

**a. Crear la cuenta.** Crea a mano la cuenta `talos-bot-leon` en github.com con un email propio y 2FA (`talos-bot` estaba ocupado). Deja activo "Keep my email addresses private": su email noreply es `335185800+talos-bot-leon@users.noreply.github.com`. Los términos de GitHub permiten una cuenta machine gratuita además de la tuya, pero la tiene que crear una persona.

**b. Colaboradora.** En `leon2995/pipeline-prueba` → Settings → Collaborators, invita a `talos-bot-leon` y acepta la invitación desde esa cuenta. En un repo personal el único nivel es escritura: puede abrir y mergear PRs, pero no cambiar la protección de ramas.

**d. Mergear T1 (cuenta-agente).** Mergea el PR a `staging` y después el de `staging` → `main`. Hasta el paso f el agente sigue trabajando como `leon2995`, y con 0 aprobaciones lo mergeas tú. CODEOWNERS y el job `hooks` tienen que estar en las dos ramas antes del paso e.

**e. Protección de ramas.** Usa endpoints parciales para no pisar lo demás (`-F` manda booleanos y enteros):

```bash
# main: 1 aprobación, code owners y descartar aprobaciones viejas ante un push nuevo
gh api -X PATCH repos/leon2995/pipeline-prueba/branches/main/protection/required_pull_request_reviews \
  -F required_approving_review_count=1 -F require_code_owner_reviews=true -F dismiss_stale_reviews=true
# staging: 0 aprobaciones y code owners
gh api -X PATCH repos/leon2995/pipeline-prueba/branches/staging/protection/required_pull_request_reviews \
  -F required_approving_review_count=0 -F require_code_owner_reviews=true
# checks obligatorios en las dos ramas: reemplaza la lista, por eso van secrets y hooks, los dos de GitHub Actions.
# Si ya marcaste node o python como obligatorios, agrégalos a la lista con el mismo app_id; si no, dejarían de exigirse.
for b in main staging; do
  printf '%s' '{"strict":false,"checks":[{"context":"secrets","app_id":15368},{"context":"hooks","app_id":15368}]}' |
    gh api -X PATCH "repos/leon2995/pipeline-prueba/branches/$b/protection/required_status_checks" --input -
  gh api -X POST "repos/leon2995/pipeline-prueba/branches/$b/protection/enforce_admins" > /dev/null
done
# verificación: los cinco campos de cada rama
for b in main staging; do
  gh api "repos/leon2995/pipeline-prueba/branches/$b/protection" --jq '{rama: "'"$b"'",
    aprobaciones: .required_pull_request_reviews.required_approving_review_count,
    code_owners: .required_pull_request_reviews.require_code_owner_reviews,
    descartar_viejas: .required_pull_request_reviews.dismiss_stale_reviews,
    enforce_admins: .enforce_admins.enabled,
    checks: [.required_status_checks.checks[] | "\(.context):\(.app_id)"]}'
done
```

Esperado: `main` con 1, `true`, `true`, `true` y `secrets:15368`, `hooks:15368`; `staging` con 0, `true`, `false`, `true` y los mismos checks. Después, a los PRs que ya estaban abiertos empújales un commit vacío (`git commit --allow-empty -m "ci: correr hooks"` y `git push`) o ciérralos y reábrelos, porque si no se quedan esperando el check `hooks`. `gh run rerun` no alcanza: repite la corrida sobre el mismo commit de merge, que es anterior al job `hooks`. No corras el pipeline entre e y f: un PR de gobierno abierto como `leon2995` ya no se podría aprobar.

**c. Token e inicio de sesión de `talos-bot-leon`.** En la cuenta `talos-bot-leon`, crea un token **classic** (Settings → Developer settings → Personal access tokens → Tokens (classic)) con vencimiento y los scopes `repo`, `read:org` y `workflow`:
- `repo` y `read:org` son el mínimo que acepta `gh auth login` con un token pegado; sin ellos responde `missing required scopes`. `public_repo` no alcanza aunque el repo sea público. `repo` solo da acceso a los repos propios de `talos-bot-leon` (hoy, ninguno) y a los repos donde es colaboradora (hoy, solo este), y `read:org` no afecta nada porque no hay organizaciones.
- `workflow` hace falta para tocar `.github/workflows/`.
- Un fine-grained token no sirve: no da acceso como colaborador a un repo personal de otra cuenta.
- **Decisión de Leonardo (2026-09-28):** el token actual tiene más scopes que el mínimo, entre ellos `admin:org`, `delete_repo` y `user`, y así se deja. La razón: `talos-bot-leon` solo tiene escritura en este repo, no tiene repos propios y no pertenece a ninguna organización (al 2026-09-28: 0 repos propios y 0 organizaciones). Por eso `repo` y `workflow` solo alcanzan este repo, y los scopes de organización o empresa (`admin:org`, `admin:org_hook`, `admin:enterprise`, `audit_log`, `write:discussion` y `write:network_configurations`) no tienen sobre qué actuar. Los demás aplican solo a la propia cuenta del bot: `user`, las llaves (`admin:public_key`, `admin:gpg_key`, `admin:ssh_signing_key`), `gist`, `notifications`, `project`, `copilot`, `codespace`, los paquetes (`write:packages`, `delete:packages`) y, sobre sus repos propios, que hoy no existen, `delete_repo` y `admin:repo_hook`. **Condición:** revisar los scopes si `talos-bot-leon` se agrega a otros repos u organizaciones, o si crea o recibe repos propios (un fork, por ejemplo), y en ese caso volver al mínimo (`repo`, `read:org`, `workflow`).

Inicia sesión de forma interactiva y pega el token cuando lo pida, con la entrada oculta. Nunca uses `echo` con el token (queda en el historial) ni lo pegues en el chat. Antes del login, guarda tu configuración de credenciales de Git para compararla después:

```bash
git config --global --get-regexp '^credential' > ~/credential-antes.txt
GH_CONFIG_DIR="$HOME/.talos-gh" gh auth login --hostname github.com --git-protocol https --insecure-storage
# 1. "Authenticate Git with your GitHub credentials?": responde No (la opción por defecto es Sí).
# 2. "How would you like to authenticate GitHub CLI?": elige "Paste an authentication token".
GH_CONFIG_DIR="$HOME/.talos-gh" gh api user --jq .login   # debe decir talos-bot-leon
GH_CONFIG_DIR="$HOME/.talos-gh" gh auth status --hostname github.com
# debe mostrar "Token: ghp_****" y, en "Token scopes", al menos 'repo', 'workflow' y 'read:org'
# (o 'admin:org', que lo incluye).
# Si dice github_pat_, es un token fine-grained: lee el repo (es público), pero git push da 403.
# Crea el classic y repite el login.
# Vencimiento real del token, en la cabecera GitHub-Authentication-Token-Expiration:
GH_CONFIG_DIR="$HOME/.talos-gh" gh api -i user | grep -i '^github-authentication-token-expiration'
gh api user --jq .login                                   # debe seguir diciendo leon2995
git config --global --get-regexp '^credential' | diff ~/credential-antes.txt - && echo sin cambios   # debe decir: sin cambios
git credential-manager github list                        # no debe aparecer talos-bot-leon (normalmente muestra solo leon2995)
ssh -T git@github.com                                     # informativo: si dice "Hi leon2995!", un remoto SSH empujaría con tu llave (lo revisa el paso f)
```

La primera pregunta importa. Si respondes Sí, `gh` le entrega el token de `talos-bot-leon` al helper que ya tienes (el Git Credential Manager): borra tu credencial de github.com, guarda la de `talos-bot-leon` en el Credential Manager de Windows, y tus `git push` desde la terminal pasan a salir como `talos-bot-leon` sin aviso. Al agente no le hace falta, porque su helper sale de la plantilla del paso f.

**Si respondiste Sí.** Lo corres tú en tu terminal, no el agente: estos comandos tocan tu Credential Manager. El hook le bloquea al agente `git credential fill|approve|reject`, `git config ... credential` y `git credential-manager`, salvo `github list`.
1. `git credential-manager github logout talos-bot-leon`
2. `git credential-manager github login --username leon2995 --device`. Antes de autorizar el código, confirma en el navegador que la sesión abierta sea `leon2995` y no `talos-bot-leon`: si el navegador tiene abierta la sesión del bot, el token guardado sería del bot aunque la etiqueta diga `leon2995`.
3. Verifica:
   - `git credential-manager github list` muestra solo `leon2995`.
   - `git config --global --get-regexp '^credential'` sale igual que antes del login. Si no tenías helper, `gh` se configura como helper global y aquí aparecen las líneas nuevas: quítalas con `git config --global --unset-all <clave>`.
   - Este comando consulta a GitHub con el token guardado, sin imprimirlo, y debe responder `leon2995`. Si responde `sin credencial guardada`, el paso 2 no guardó nada: repítelo. Si `gh` muestra un error HTTP (por ejemplo 401), hay credencial, pero el token guardado no es válido: también repite el paso 2. La etiqueta `username=` de `git credential fill` no alcanza, porque es la que pusiste con `--username`.

     ```bash
     printf 'protocol=https\nhost=github.com\nusername=leon2995\n\n' | git credential fill | sed -n 's/^password=//p' | { read -r t; if [ -n "$t" ]; then GH_TOKEN="$t" gh api user --jq .login; else echo 'sin credencial guardada'; fi; }
     ```

Con `--insecure-storage` y la respuesta No, el token de `talos-bot-leon` queda en `~/.talos-gh/hosts.yml` y no en el keyring ni en el Credential Manager. Aun así, en `gh` 2.92.0 el login marca a `talos-bot-leon` como la cuenta activa y reescribe la entrada compartida del keyring de Windows. Tu cuenta conserva su propia entrada. Si `gh api user --jq .login` sin `GH_CONFIG_DIR` deja de decir `leon2995`, corre `gh auth switch --hostname github.com --user leon2995`, y si no alcanza, `gh auth login`.

- **Vence: 2026-10-28** (hora local; 2026-10-29 02:05 UTC). **Rotarlo antes del 2026-10-15.** Token classic creado el 2026-09-28; GitHub responde `2026-10-29 02:05:13 UTC` en la cabecera `GitHub-Authentication-Token-Expiration`, que se ve con `GH_CONFIG_DIR="$HOME/.talos-gh" gh api -i user | grep -i '^github-authentication-token-expiration'`. Para rotarlo: crea uno nuevo, repite el login de este paso (respondiendo No a la pregunta de Git) y revoca el viejo.

**f. Conectar al agente.** Copia `.claude/settings.local.example.json` como `.claude/settings.local.json`. Si ya existe (Claude Code lo crea al guardar permisos), fusiona solo el bloque `env`. Completa `GH_CONFIG_DIR` con la ruta real (`C:/Users/<tu usuario>/.talos-gh`). El email noreply de `talos-bot-leon` (`335185800+talos-bot-leon@users.noreply.github.com`, de Settings → Emails de esa cuenta) ya viene en la plantilla. El archivo no lleva el token. Reinicia la sesión de Claude Code para que tome el `env` nuevo.

Verifica desde la sesión reiniciada con el modo `!` de Claude Code, que corre el comando en la sesión con su `env` y no pasa por el hook. En tu terminal esas variables no existen, y a través del agente el hook bloquea estos comandos:

```bash
! git config --show-origin --get-regexp '^credential\..*helper$'
# deben aparecer dos líneas "command line: credential.https://github.com.helper": la primera vacía y la
# segunda "!gh auth git-credential". El valor vacío anula, para github.com, el helper del sistema
# (credential.helper manager) que aparece arriba.
! git config --get-urlmatch credential.helper https://github.com   # debe decir: !gh auth git-credential
! gh api user --jq .login                                          # debe decir: talos-bot-leon
! git remote -v                                                    # todas las líneas, fetch y push: https://github.com/... sin usuario
! git var GIT_AUTHOR_IDENT; git var GIT_COMMITTER_IDENT            # las dos: talos-bot-leon <335185800+talos-bot-leon@users.noreply.github.com>
! [ -z "${GH_TOKEN-}${GITHUB_TOKEN-}" ] && echo sin variables de token   # debe decir: sin variables de token
```

Por qué cada una:
- `git remote -v`: si un remoto es SSH (`git@github.com:...`) o lleva usuario, el push sale con tu llave o tu credencial. El hook solo revisa el remoto que aparece en el comando (u `origin` si no aparece), y puede confundirlo con el valor de una opción como `-o`. Por eso deja un solo remoto, `origin`, en HTTPS: `git remote set-url origin https://github.com/leon2995/pipeline-prueba.git`, y `git remote set-url --push origin ...` si tiene una URL de push aparte.
- `git var`: el hook compara solo el nombre del autor y del committer, pero GitHub atribuye los commits por el email. Si el email no es el noreply de `talos-bot-leon` con su ID numérico, el commit queda a tu nombre o sin cuenta.
- Variables de token: el hook no reconoce todas las formas de imprimir el entorno (por ejemplo `export  -p` con dos espacios o `env FOO="a b"`), así que la sesión no debe tener ningún token en el entorno.

**g. Activación y verificación conjunta.** Con el agente ya como `talos-bot-leon`:
1. El agente abre un PR sin rutas de gobierno con la fecha de vencimiento en este archivo. Lo mergea a `staging` con 0 aprobaciones.
2. El agente abre un PR de gobierno que crea `.claude/identidad-agente.txt` con `talos-bot-leon`. Tiene que quedar bloqueado hasta tu aprobación como code owner; lo apruebas y lo mergeas. Con ese archivo en `staging`, el hook exige la identidad de `talos-bot-leon` para commits, push y escrituras en GitHub.

3. En cada PR de prueba, revisa en GitHub quién hizo cada push y cada commit. Tienen que ser de `talos-bot-leon`, no de `leon2995`:

   ```bash
   gh api repos/leon2995/pipeline-prueba/activity --jq '.[0:5][] | {ref, tipo: .activity_type, actor: .actor.login}'
   gh pr view <n> --json author,commits --jq '{autor: .author.login, commits: [.commits[].authors[].login]}'
   git credential-manager github list   # desde tu terminal: no debe aparecer talos-bot-leon
   ```

   Si algún push o commit del agente sale como `leon2995` (o vacío), o tus propios pushes salen como `talos-bot-leon`, detén el pipeline y repite las verificaciones de los pasos c y f antes de seguir.

4. Con `.claude/identidad-agente.txt` activo, el agente verifica que un push normal pase (`git push -u origin <rama>`, `git push` sin remoto y `git push 2>&1 | tail -3`) y que su commit y su push salgan como `talos-bot-leon`.

Si en el punto 1 GitHub pide una aprobación, o en el punto 2 no la pide, el comportamiento de "code owners con 0 aprobaciones" no es el esperado. La alternativa es subir `staging` a 1 aprobación (y entonces apruebas todo PR a `staging`) o usar un ruleset con la revisión de code owners.

## 5. Primera corrida

Abre Claude Code en el repo (o desde la app móvil de Claude) y escribe:

> Lee CLAUDE.md. Vamos a hacer una tarea de prueba de riesgo bajo: agrega un endpoint GET /health que responda {"ok": true}. Sigue el protocolo completo hasta el PR a staging.

Qué debes ver, en orden: plan corto con criterios, test-writer creando `tests/acceptance/`, engineer implementando en `feat/T1-health`, hook de tests, auditor con JSON, `python scripts/jev.py` con PASS, `gh pr create`. Si algo se salta, dile "revisa el protocolo, te saltaste el paso X" y ajusta el CLAUDE.md si hace falta.

## 6. Cambiar de modo

En cualquier momento: "cambia a paso-a-paso" o "sigue en automatico". El CTO actualiza `.pipeline/modo`.

## Notas

- Los flags exactos de la CLI de Railway cambian entre versiones. Si `railway variables --kv` o `railway environment link <nombre>` no existen en tu versión, corre `railway --help` y ajusta `.claude/commands/verificar-deploy.md`. El hook solo le deja al agente las lecturas de railway (lista en `guard-commands.sh`); si una lectura nueva que necesitas se bloquea, agrégala a esa lista en un PR de gobierno.
- `gitleaks-action` es gratis para cuentas personales; para organizaciones pide licencia. Si estorba, quita el job `secrets` y agrega el check de gitleaks como pre-commit local.
- Los tokens (`gh`, `railway`, `codex`) viven en tu máquina, nunca en el repo. `.env` está en `.gitignore` y bloqueado para todos los agentes. El de `talos-bot-leon` vive en `~/.talos-gh/hosts.yml` (paso 4b.c), con lectura y escritura denegadas al agente.

## 7. Fase 2 (después de 15 o 20 tareas)

Operación desatendida con Hermes Agent como gateway (WhatsApp o Telegram, cron, reportes). Todo lo que Hermes necesita ya existe en este paquete: `scripts/run-task.sh`, `scripts/resume-task.sh` y el estado en `.pipeline/`. El plan está en `docs/FASE-2-HERMES.md`. No lo arranques antes de tener métricas de Fase 1.
