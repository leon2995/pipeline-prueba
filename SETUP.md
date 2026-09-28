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

# jq (opcional: si falta, los hooks usan python3)
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

1. Settings → Branches → Add rule para `main`:
   - Require a pull request before merging, con 0 aprobaciones requeridas. GitHub no deja aprobar tu propio PR, y los PR los abre tu cuenta; tu "aprobación" es mergear tú mismo desde la web o la app.
   - Require status checks to pass: marca `secrets` ahora y `node` o `python` en cuanto aparezcan (GitHub solo los lista después de que corren una vez).
   - Do not allow bypassing the above settings.
2. Misma regla para `staging`.
3. En repos privados de cuentas personales gratuitas, la protección de ramas no está disponible (requiere GitHub Pro, Team o una organización con plan). Para el repo de práctica usa uno público.

## 4b. Cuenta del agente (`talos-bot`) y CODEOWNERS

El agente trabaja con su propia cuenta de GitHub para que el servidor pueda exigir tu aprobación como code owner en los PRs de gobierno (`.github/CODEOWNERS`, derivado de `.claude/rutas-gobierno.txt`). Los pasos van en este orden: **a, b, d, e, c, f, g**. Corre todos los comandos en tu terminal, no a través del agente: el hook bloquea los que nombran tokens, `GH_CONFIG_DIR` o `~/.talos-gh`.

**a. Crear la cuenta.** Crea a mano la cuenta `talos-bot` en github.com con un email propio y 2FA. Los términos de GitHub permiten una cuenta machine gratuita además de la tuya, pero la tiene que crear una persona.

**b. Colaboradora.** En `leon2995/pipeline-prueba` → Settings → Collaborators, invita a `talos-bot` y acepta la invitación desde esa cuenta. En un repo personal el único nivel es escritura: puede abrir y mergear PRs, pero no cambiar la protección de ramas.

**d. Mergear T1 (cuenta-agente).** Mergea el PR a `staging` y después el de `staging` → `main`. Hasta el paso f el agente sigue trabajando como `leon2995`, y con 0 aprobaciones lo mergeas tú. CODEOWNERS y el job `hooks` tienen que estar en las dos ramas antes del paso e.

**e. Protección de ramas.** Usa endpoints parciales para no pisar lo demás (`-F` manda booleanos y enteros):

```bash
# main: 1 aprobación, code owners y descartar aprobaciones viejas ante un push nuevo
gh api -X PATCH repos/leon2995/pipeline-prueba/branches/main/protection/required_pull_request_reviews \
  -F required_approving_review_count=1 -F require_code_owner_reviews=true -F dismiss_stale_reviews=true
# staging: 0 aprobaciones y code owners
gh api -X PATCH repos/leon2995/pipeline-prueba/branches/staging/protection/required_pull_request_reviews \
  -F required_approving_review_count=0 -F require_code_owner_reviews=true
# checks obligatorios en las dos ramas: reemplaza la lista, por eso van secrets y hooks, los dos de GitHub Actions
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

Esperado: `main` con 1, `true`, `true`, `true` y `secrets:15368`, `hooks:15368`; `staging` con 0, `true`, `false`, `true` y los mismos checks. Después, vuelve a correr el CI de los PRs que ya estaban abiertos (`gh run rerun <id>` o un push vacío), porque si no se quedan esperando el check `hooks`. No corras el pipeline entre e y f: un PR de gobierno abierto como `leon2995` ya no se podría aprobar.

**c. Token e inicio de sesión de `talos-bot`.** En la cuenta `talos-bot`, crea un token **classic** (Settings → Developer settings → Personal access tokens → Tokens (classic)) con vencimiento y los scopes `public_repo` y `workflow`. `public_repo` solo sirve para repos públicos; un repo privado necesita `repo`. `workflow` hace falta para tocar `.github/workflows/`. Un fine-grained token no sirve: no da acceso como colaborador a un repo personal de otra cuenta. Inicia sesión de forma interactiva y pega el token cuando lo pida, con la entrada oculta. Nunca uses `echo` con el token (queda en el historial) ni lo pegues en el chat:

```bash
GH_CONFIG_DIR="$HOME/.talos-gh" gh auth login --hostname github.com --git-protocol https --insecure-storage
# elige "Paste an authentication token"
GH_CONFIG_DIR="$HOME/.talos-gh" gh api user --jq .login   # debe decir talos-bot
gh api user --jq .login                                   # debe seguir diciendo leon2995
```

Con `--insecure-storage` el token queda en `~/.talos-gh/hosts.yml` y no toca el keyring de Windows. Si tu cuenta dejara de responder como `leon2995`, vuelve a iniciar tu sesión con `gh auth login`.

- **Vence: AAAA-MM-DD** (completar en el paso c). Rota el token 14 días antes: crea uno nuevo, repite el login de este paso y revoca el viejo.

**f. Conectar al agente.** Copia `.claude/settings.local.example.json` como `.claude/settings.local.json`. Si ya existe (Claude Code lo crea al guardar permisos), fusiona solo el bloque `env`. Completa `GH_CONFIG_DIR` con la ruta real (`C:/Users/<tu usuario>/.talos-gh`) y el email noreply de `talos-bot`. Lo encuentras en Settings → Emails de esa cuenta y tiene la forma `<id>+talos-bot@users.noreply.github.com`. El archivo no lleva el token. Reinicia la sesión de Claude Code para que tome el `env` nuevo. Para verificar el helper de credenciales:

```bash
git config --show-origin --get-regexp '^credential\..*helper$'
# deben aparecer dos líneas "command line: credential.https://github.com.helper": la primera vacía y la
# segunda "!gh auth git-credential". El valor vacío anula, para github.com, el helper del sistema
# (credential.helper manager) que aparece arriba.
git config --get-urlmatch credential.helper https://github.com   # debe decir: !gh auth git-credential
```

**g. Activación y verificación conjunta.** Con el agente ya como `talos-bot`:
1. El agente abre un PR sin rutas de gobierno con la fecha de vencimiento en este archivo. Lo mergea a `staging` con 0 aprobaciones.
2. El agente abre un PR de gobierno que crea `.claude/identidad-agente.txt` con `talos-bot`. Tiene que quedar bloqueado hasta tu aprobación como code owner; lo apruebas y lo mergeas. Con ese archivo en `staging`, el hook exige la identidad de `talos-bot` para commits, push y escrituras en GitHub.

Si en el punto 1 GitHub pide una aprobación, o en el punto 2 no la pide, el comportamiento de "code owners con 0 aprobaciones" no es el esperado. La alternativa es subir `staging` a 1 aprobación (y entonces apruebas todo PR a `staging`) o usar un ruleset con la revisión de code owners.

## 5. Primera corrida

Abre Claude Code en el repo (o desde la app móvil de Claude) y escribe:

> Lee CLAUDE.md. Vamos a hacer una tarea de prueba de riesgo bajo: agrega un endpoint GET /health que responda {"ok": true}. Sigue el protocolo completo hasta el PR a staging.

Qué debes ver, en orden: plan corto con criterios, test-writer creando `tests/acceptance/`, engineer implementando en `feat/T1-health`, hook de tests, auditor con JSON, `python scripts/jev.py` con PASS, `gh pr create`. Si algo se salta, dile "revisa el protocolo, te saltaste el paso X" y ajusta el CLAUDE.md si hace falta.

## 6. Cambiar de modo

En cualquier momento: "cambia a paso-a-paso" o "sigue en automatico". El CTO actualiza `.pipeline/modo`.

## Notas

- Los flags exactos de la CLI de Railway cambian entre versiones. Si `railway variables --kv` o `railway environment <nombre>` no existen en tu versión, corre `railway --help` y ajusta `.claude/commands/verificar-deploy.md`.
- `gitleaks-action` es gratis para cuentas personales; para organizaciones pide licencia. Si estorba, quita el job `secrets` y agrega el check de gitleaks como pre-commit local.
- Los tokens (`gh`, `railway`, `codex`) viven en tu máquina, nunca en el repo. `.env` está en `.gitignore` y bloqueado para todos los agentes. El de `talos-bot` vive en `~/.talos-gh/hosts.yml` (paso 4b.c), con lectura y escritura denegadas al agente.

## 7. Fase 2 (después de 15 o 20 tareas)

Operación desatendida con Hermes Agent como gateway (WhatsApp o Telegram, cron, reportes). Todo lo que Hermes necesita ya existe en este paquete: `scripts/run-task.sh`, `scripts/resume-task.sh` y el estado en `.pipeline/`. El plan está en `docs/FASE-2-HERMES.md`. No lo arranques antes de tener métricas de Fase 1.
