# Criterios: T3b (instalador v1)

Riesgo: **bajo**. Es un script local que copia archivos a otro repo y crea una rama local. No toca GitHub, Railway ni el remoto, no agrega dependencias y no toca rutas de gobierno de este repo: `instalador/`, `tests/`, `package.json` y `package-lock.json` no están en `.claude/rutas-gobierno.txt`. Va con el protocolo normal: test-writer, engineer, auditor Claude y JEV. Alcance definido por Leonardo: copia el framework sin pisar archivos, crea `staging`, genera `.railway/railway.ts` con la política de reinicio ON_FAILURE y 3 reintentos, e imprime los comandos exactos de los pasos manuales. Simula por defecto; con `--aplicar` solo escribe archivos locales y la rama `staging` local. Quedan fuera: automatizar Railway y GitHub, migrar este repo a `railway.ts` y la prueba de punta a punta. El primer proyecto real hace de prueba de punta a punta.

## Plan

1. test-writer: `tests/acceptance/test-instalador.sh` (bash, sin dependencias), que falla ahora.
2. engineer, en su worktree y en la rama `feat/T3b-instalador`: `instalador/instalar.sh`, `instalador/manifiesto.txt`, las plantillas que hagan falta en `instalador/`, pruebas unitarias en `tests/unit/`, `package.json` sin dependencias cuyo `npm test` corra las pruebas de aceptación y las unitarias, y `package-lock.json` (con `npm install --package-lock-only`) para que `npm ci` funcione en CI.
3. Auditor Claude, JEV con riesgo bajo, PR contra `staging`; con PASS y CI en verde, merge a `staging`.

## Interfaces

- **Invocación:** `bash instalador/instalar.sh <destino> [--aplicar] [--modo nuevo|existente] [--servicio NOMBRE] [--puerto N]`.
  - La fuente del framework es el repo donde vive el script: el padre de `instalador/`.
  - `<destino>` es la ruta a un repo git.
- **Salida estándar**, líneas con prefijo fijo para que las pruebas las lean:
  - por cada archivo: `crear <ruta>`, `igual <ruta>` o `conflicto <ruta>`, con la ruta relativa al destino y `/` como separador;
  - `modo nuevo` o `modo existente`;
  - `rama staging: crear`, `rama staging: existe` o `rama staging: sin commits`;
  - una línea `== Pasos manuales` y, después, los comandos.
- **Códigos de salida:**
  - `0`: todo bien y sin conflictos;
  - `3`: hubo al menos un conflicto;
  - `2`: error de uso, que es un destino que no existe, que no es un repo git, una opción desconocida, un `--modo` inválido o un `--puerto` que no es un número.

## Criterios

- **C1. Simulación por defecto.** Sin `--aplicar`, el destino queda idéntico: mismos archivos y contenido, mismas ramas y el mismo `git status`. Aun así imprime el plan completo (archivos, modo, rama y pasos manuales).
- **C2. Qué se copia.** `instalador/manifiesto.txt` lista una ruta por línea, relativa a la fuente, y admite comentarios con `#` y líneas vacías.
  - **Lista:** `CLAUDE.md`, `LESSONS.md`, `.gitattributes`, `.gitignore`, los agentes, comandos, prompts y hooks de `.claude/`, `.claude/rutas-gobierno.txt`, `.claude/settings.json`, `.claude/settings.local.example.json`, `.claude/pipeline.conf`, `.github/CODEOWNERS`, `.github/workflows/ci.yml`, `docs/adr/0000-plantilla.md`, `scripts/jev.py`, `scripts/test-hooks.sh`, `scripts/run-task.sh`, `scripts/resume-task.sh`, `scripts/watch-deploy.sh`, `.pipeline/README.md` y `.pipeline/urls.json`.
  - **Nunca se copian:** `.claude/settings.local.json`, `.claude/identidad-agente.txt`, `.claude/worktrees/`, el estado de `.pipeline/` de este repo (criterios, evidencia, veredictos, `test-hooks-salida.txt`, `lecciones-pendientes.md`, `plan.json`, `modo`), `tests/`, `instalador/`, `package.json`, `package-lock.json`, `SETUP.md`, `README.md`, `railway.json` y `docs/FASE-2-HERMES.md`.
  - Toda ruta del manifiesto existe en la fuente. Una prueba recorre el manifiesto y lo verifica.
- **C3. No pisar.** Con `--aplicar`, un archivo que no existe en el destino se crea con el contenido de la fuente (`crear`). Uno que existe igual se deja como está (`igual`). Uno que existe distinto no se toca (`conflicto`) y queda byte a byte como estaba.
  - Con al menos un conflicto, el código de salida es 3 y los demás archivos se escriben igual.
  - Por cada conflicto, los pasos manuales traen el comando para ver las diferencias (`diff <fuente>/<ruta> <destino>/<ruta>`).
  - Una segunda corrida con `--aplicar` informa todo como `igual` y sale con 0.
- **C4. Archivos generados.** Son estos, y se crean solo si no existen; si existen, cuentan como `igual` o `conflicto` según su contenido:
  - `.pipeline/lecciones-pendientes.md`, con el encabezado del flujo y "Ninguna" en pendientes, sin el historial de este repo;
  - `.pipeline/plan.json`;
  - `.railway/railway.ts`, con `import { defineRailway, project, service } from 'railway/iac'`, el servicio `<servicio>` con `healthcheck: '/health'`, `healthcheckTimeout: 120` y `deploy: { restartPolicyType: 'ON_FAILURE', restartPolicyMaxRetries: 3 }`, dentro de `project('<repo>', ...)`.

  Valores por defecto: `<servicio>` es el nombre del repo; `<repo>` sale de la URL de `origin` (`https://github.com/<dueño>/<repo>.git`) o, sin `origin`, del nombre de la carpeta del destino.
- **C5. Modos.**
  - **Detección:** para decidir el modo no cuentan las rutas del manifiesto ni las que genera el instalador (`.pipeline/lecciones-pendientes.md`, `.pipeline/plan.json`, `.pipeline/criterios-T1.md`, `.railway/railway.ts`). De los archivos versionados que quedan, un repo sin ninguno, o solo con `README*`, `LICENSE*`, `.gitignore` o `.gitattributes`, es `nuevo`. Con cualquier otro es `existente`. `--modo` fuerza el modo.
    - Consecuencia: una corrida sobre un repo que ya tiene el framework commiteado sigue en `modo nuevo` y deja todo `igual`.
    - *Cambio aceptado por Leonardo después del PR #16:* el engineer eligió este comportamiento y el criterio original contaba cualquier archivo versionado.
  - **Modo nuevo:** `plan.json` queda con la plantilla vacía de subtareas.
  - **Modo existente:** `plan.json` trae una subtarea T1 "ADR del stack actual", con el archivo esperado `docs/adr/0001-stack-actual.md`, y se genera `.pipeline/criterios-T1.md` con criterios verificables para ese ADR. Los criterios nombran los manifiestos detectados en el destino (`package.json`, `pyproject.toml`, `go.mod`, `requirements.txt`, `Cargo.toml`, `Gemfile`, `Dockerfile`) como pista.
- **C6. Rama `staging`.** Con `--aplicar`:
  - si el destino tiene al menos un commit y no hay rama `staging`, se crea la rama local `staging` en `HEAD` (`rama staging: crear`), sin cambiar la rama activa;
  - si ya existe, no se toca (`rama staging: existe`);
  - si no hay commits, no se crea (`rama staging: sin commits`).

  Nunca hace commit, push, fetch ni ningún cambio en el remoto, y no llama a `gh` ni a `railway`. Las pruebas lo verifican con `gh` y `railway` falsos en el PATH que registran cualquier llamada, y con un remoto de prueba cuyas referencias no cambian.
- **C7. Pasos manuales.** Después de `== Pasos manuales` van los comandos exactos, con `<dueño>`, `<repo>`, `<servicio>` y `<puerto>` ya reemplazados (puerto por defecto 8080), en este orden:
  1. **Git:** revisar y commitear el framework en la rama activa, actualizar `staging` con `git merge --ff-only` desde la rama activa y `git push -u origin <rama-activa> staging`.
  2. **GitHub, con la cuenta del dueño:**
     - invitar a `talos-bot-leon` (el bot sale de `.claude/pipeline.conf`) con `gh api -X PUT repos/<dueño>/<repo>/collaborators/<bot> -f permission=push`;
     - aceptar la invitación con la configuración de gh del bot (`GH_CONFIG_DIR="$HOME/.talos-gh" gh api user/repository_invitations` y `gh api -X PATCH user/repository_invitations/<id>`);
     - la protección, después de que el CI corrió una vez en las dos ramas: `gh api -X PUT repos/<dueño>/<repo>/branches/<rama>/protection --input -` con el JSON de `main` (1 aprobación, code owners, `dismiss_stale_reviews`, `enforce_admins`, checks `secrets` y `hooks` con `app_id` 15368, sin force push ni borrado) y el de `staging` (0 aprobaciones, code owners, `enforce_admins`, los mismos checks);
     - el GET que verifica la protección de las dos ramas.
  3. **Railway, en la terminal del dueño:**
     - `railway init --name <repo>` (o `railway link` si el proyecto ya existe);
     - `railway add --service <servicio> --repo <dueño>/<repo> --branch main`;
     - `railway environment new staging --duplicate production --service-config <servicio> source.branch staging`;
     - `railway variable set PORT=<puerto> --service <servicio> --environment <ambiente> --skip-deploys` y `railway domain --port <puerto> --service <servicio> --environment <ambiente>`, para `production` y para `staging`;
     - `npm install --save-dev railway@3.11.0`, el SDK que pide `railway.ts`, con Node 22 o más;
     - para cada ambiente: `railway environment link <ambiente>`, `railway config plan` y `railway config apply`.
  4. **Agente:**
     - copiar `.claude/settings.local.example.json` a `.claude/settings.local.json` y completar `GH_CONFIG_DIR`;
     - reiniciar la sesión de Claude Code;
     - crear `.claude/identidad-agente.txt` con el bot, por PR de gobierno.

  Ningún comando impreso contiene un token ni pide imprimirlo.
- **C8. Errores de uso.** Salen con código 2, un mensaje en stderr y sin tocar el destino:
  - sin argumentos;
  - un destino que no existe;
  - una carpeta que no es un repo git;
  - una opción desconocida;
  - `--modo` con un valor inválido;
  - `--puerto` no numérico.
- **C9. Pruebas en CI.** `package.json` no tiene dependencias, y `npm test` corre las pruebas de aceptación y las unitarias del instalador. `package-lock.json` hace que `npm ci` funcione. El job `node` del CI y el hook Stop del engineer (`run-tests.sh`) las corren.
- **C10. Portabilidad.** Funciona con el bash de Git para Windows y en Linux (el runner de CI). Solo usa bash, coreutils, git y sed o awk (sin extensiones de gawk). Las rutas del destino pueden tener espacios.

Verificación posterior al PASS (fuera de los criterios del auditor): el CI del PR en verde, con el job `node` corriendo las pruebas, y la simulación sobre un repo descartable leída por Leonardo.
