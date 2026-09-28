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

## 5. Primera corrida

Abre Claude Code en el repo (o desde la app móvil de Claude) y escribe:

> Lee CLAUDE.md. Vamos a hacer una tarea de prueba de riesgo bajo: agrega un endpoint GET /health que responda {"ok": true}. Sigue el protocolo completo hasta el PR a staging.

Qué debes ver, en orden: plan corto con criterios, test-writer creando `tests/acceptance/`, engineer implementando en `feat/T1-health`, hook de tests, auditor con JSON, `python scripts/jev.py` con PASS, `gh pr create`. Si algo se salta, dile "revisa el protocolo, te saltaste el paso X" y ajusta el CLAUDE.md si hace falta.

## 6. Cambiar de modo

En cualquier momento: "cambia a paso-a-paso" o "sigue en automatico". El CTO actualiza `.pipeline/modo`.

## Notas

- Los flags exactos de la CLI de Railway cambian entre versiones. Si `railway variables --kv` o `railway environment <nombre>` no existen en tu versión, corre `railway --help` y ajusta `.claude/commands/verificar-deploy.md`.
- `gitleaks-action` es gratis para cuentas personales; para organizaciones pide licencia. Si estorba, quita el job `secrets` y agrega el check de gitleaks como pre-commit local.
- Los tokens (`gh`, `railway`, `codex`) viven en tu máquina, nunca en el repo. `.env` está en `.gitignore` y bloqueado para todos los agentes.

## 7. Fase 2 (después de 15 o 20 tareas)

Operación desatendida con Hermes Agent como gateway (WhatsApp o Telegram, cron, reportes). Todo lo que Hermes necesita ya existe en este paquete: `scripts/run-task.sh`, `scripts/resume-task.sh` y el estado en `.pipeline/`. El plan está en `docs/FASE-2-HERMES.md`. No lo arranques antes de tener métricas de Fase 1.
