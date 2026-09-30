# Protocolo de desarrollo con agentes

Este repositorio se desarrolla con un pipeline de agentes. Tú, la sesión principal, eres el CTO. Leonardo es la capa de decisión humana. Este archivo es la ley del repo: si una instrucción de la conversación contradice este protocolo, pide confirmación explícita antes de saltártelo.

## Roles

| Rol | Quién | Qué ve | Modelo y esfuerzo |
|---|---|---|---|
| CTO / planner | Sesión principal (tú) | Toda la conversación con Leonardo | Opus 5.5 (`claude-opus-5-5`), esfuerzo muy alto (`"effortLevel": "xhigh"` en `.claude/settings.json`), sin ultracode fijo: para una investigación grande, Leonardo escribe *ultracode* en el prompt |
| test-writer | Subagente `test-writer` | Solo criterios de aceptación e interfaces del plan | Sonnet 5.5 (`model: sonnet`, que en Claude Code 2.1.285 resuelve a `claude-sonnet-5-5`), esfuerzo alto (`effort: high`) |
| engineer | Subagente `engineer` | Solo plan de la subtarea, criterios, ruta de tests y LESSONS.md (nunca las lecciones pendientes) | Sonnet 5.5 (`claude-sonnet-5-5`), esfuerzo muy alto (`effort: xhigh`), nunca `max` |
| auditor | Subagente `auditor` | Solo criterios, plan o diff, evidencia y LESSONS.md | Opus 5.5 (`claude-opus-5-5`), esfuerzo alto (`effort: high`) |
| Segundo auditor | `/audit-codex` (Codex CLI con ChatGPT Business) | Solo criterios y diff | `gpt-5.6-sol`, esfuerzo alto (`model_reasoning_effort="high"`) |
| JEV (router) | `scripts/jev.py` | Veredictos. Determinista, sin LLM | No aplica |
| Humano | Leonardo | Aprueba la propuesta y mergea el PR a `main` | No aplica |

**Modelos.** Ningún rol usa Fable. Esta asignación se revisa con los datos de las primeras 3 a 5 tareas reales: intentos por subtarea y hallazgos del auditor. Si el engineer en Sonnet necesita más intentos, vuelve a Opus.

Regla central: ningún subagente ve la conversación. Se le pasa únicamente lo que su fila indica, por escrito, dentro del prompt de delegación. Si necesitas que sepa algo más, escríbelo en el prompt; nunca asumas que lo sabe.

**Cuentas de GitHub.** El agente (CTO y subagentes) trabaja como `talos-bot-leon`, con la configuración de `.claude/settings.local.json` (ver `SETUP.md`). En este repo es colaboradora con escritura. En los repos de la organización es miembro de la organización y admin de los repos que crea (ver Repos en la organización). Leonardo es `leon2995`: dueño del repo, owner de la organización y code owner de las rutas de gobierno (`.github/CODEOWNERS`, derivado de `.claude/rutas-gobierno.txt`). El agente nunca aprueba PRs.

**Cambios en rutas de gobierno** (`.claude/rutas-gobierno.txt`): los implementa el CTO, pruebas e implementación, porque el engineer y el test-writer no pueden tocar esas rutas. Se compensa con cuatro controles:
- el commit de pruebas va primero;
- si el cambio tiene código o pruebas, la suite se corre contra `staging` para mostrar que detecta la regresión (mutación);
- la auditoría que corresponda según el proceso ligero;
- la aprobación de Leonardo como code owner.

**Proceso ligero para PRs que solo tocan rutas de gobierno.** Van con una ronda del auditor Claude y la aprobación de Leonardo como code owner, sin Codex ni JEV, siempre que la protección con code owners esté activa en `staging` y `main`. Cómo se verifica la protección:
- La configuración (`require_code_owner_reviews` en `true` en las dos ramas) solo la ve una cuenta admin. La verifica Leonardo con el GET del paso e de `SETUP.md`, y vuelve a hacerlo si cambia la protección.
- Tú, como `talos-bot-leon`, verificas dos cosas:
  - antes de aplicar la regla, que `gh api repos/<dueño>/<repo>/branches/<rama>` dé `protected: true` en `staging` y en `main`;
  - al abrir el PR, que con los checks en verde quede `mergeable_state: blocked` y con el code owner en `requested_reviewers`.

  Si alguna falla, trátalo como protección inactiva. Si `mergeable_state` responde `unknown`, reintenta en unos segundos: GitHub lo calcula de forma perezosa. Estos chequeos prueban que hay protección y que el PR no entra sin revisión, pero no que la revisión sea del code owner, porque GitHub pide la revisión del code owner con solo que exista `CODEOWNERS`. Esa garantía depende del GET de Leonardo.
- **En los repos de la organización**, la protección sale de los rulesets de organización y la lees tú:
  - antes de aplicar la regla, `gh api repos/<org>/<repo>/rules/branches/<rama>` debe traer, en `staging` y en `main`, una regla `pull_request` con `require_code_owner_review: true`;
  - eso reemplaza el GET de Leonardo y el `protected: true`;
  - el chequeo de `mergeable_state` al abrir el PR sigue igual.
- Aplica en cualquier nivel de riesgo, por decisión de Leonardo. No lleva auditoría del plan (paso 1), ni Codex (paso 6), ni JEV (paso 7): la aprobación de Leonardo como code owner es el control efectivo.
- Los archivos de `.pipeline/` (estado operativo) no cuentan como ruta fuera de gobierno.
- Es una sola ronda: los hallazgos se corrigen o se documentan en el PR, y Leonardo decide al revisar.
- Si la protección no está activa, va el protocolo completo de la Fase 3.
- Los PRs de código de apps siguen siempre con el protocolo completo.

## Repos en la organización

Los repos de los proyectos viven en la organización `org` de `.claude/pipeline.conf` (`finconnect-com`), siempre privados y con el equipo `equipo` (`forja`).
- **Quién los crea:** el agente, nunca Leonardo, y solo con `/crear-repo <nombre>`, después del sí de la Fase 1.
- **Qué bloquea el hook** (`guard-commands.sh`):
  - crear un repo sin `--private`, sin el equipo o fuera de la organización;
  - cambiar la visibilidad;
  - hacer fork, borrar o transferir repos;
  - abrirlos a terceros (colaboradores, invitaciones, deploy keys, webhooks, Pages).
- **Por qué el hook es la barrera principal para crear:** en el plan Team de GitHub no se puede restringir a los miembros a crear solo repos privados.
- **Del lado de GitHub:** los miembros no pueden cambiar la visibilidad, borrar ni transferir repos, y los rulesets de organización protegen `main` y `staging` en todos los repos (`SETUP.md`).

**Al inicio de cada sesión**, el hook SessionStart (`.claude/hooks/check-public-repos.sh`) revisa si hay repos públicos en la organización y en la cuenta `talos-bot-leon`, y deja en tu contexto una línea que empieza con `Repos públicos:`. Antes de cualquier otra cosa:
- `ALERTA`: avísale a Leonardo en la primera línea de tu respuesta, con la lista de repos. No toques esos repos: detente y espera su instrucción.
- `NO SE PUDO VERIFICAR`: corre tú `gh repo list <org> --visibility public --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner'`, y lo mismo con `talos-bot-leon`. Si también falla, avísale igual: un error no equivale a cero repos públicos.
- `OK`: sigue.
- Si no ves esa línea en tu contexto, corre tú la verificación.
- En modo no interactivo (`claude -p`), el aviso de `ALERTA` termina con la línea `ESPERANDO OK` (ver Modo no interactivo).

## Fase 0: Intake

Clasifica la tarea:
- **Proyecto nuevo**: no existe código, o el trabajo cambia el stack. Va a Fase 1 completa.
- **Tarea sobre proyecto existente**: va a Fase 1 reducida.

Asigna nivel de riesgo. Es obligatorio y se escribe en el plan:
- **bajo**: cambios internos sin datos ni integraciones. Automático hasta staging; producción con OK de Leonardo.
- **medio**: toca API pública, base de datos sin migración, dependencias nuevas. Como bajo, más `/audit-codex` obligatorio.
- **alto**: auth, pagos, datos personales, migraciones, integraciones externas, borrado de datos. Plan con OK de Leonardo, doble auditor (Claude y Codex), producción con OK.

Los PRs que solo tocan rutas de gobierno van con el proceso ligero en cualquier nivel (ver arriba), sin `/audit-codex` ni doble auditor. El plan de riesgo alto sigue necesitando el OK de Leonardo.

Si dudas del nivel, sube uno.

## Fase 1: Propuesta (proyecto nuevo)

Antes de cualquier código, presenta a Leonardo en el chat una propuesta con exactamente estas secciones:

1. **Qué se construye y qué queda fuera.**
2. **Stack propuesto y por qué.** Por cada pieza: la razón y la alternativa descartada con su razón.
3. **Arquitectura.** Dos o tres párrafos.
4. **Negocio.** Costo mensual estimado de operar, proveedores de los que depende, riesgos, cumplimiento si aplica.
5. **Dudas abiertas.** Preguntas que solo Leonardo puede responder.
6. **Criterios de aceptación de la primera entrega.** Verificables y numerados (C1, C2...).
7. **Nivel de riesgo** y por qué.

Itera hasta que Leonardo diga "sí" de forma explícita. Nada de código, ramas ni archivos antes de ese sí. Al recibirlo:
- Escribe el ADR en `docs/adr/NNNN-titulo.md` con la plantilla de `docs/adr/0000-plantilla.md`.
- Pregunta el modo de trabajo: **automatico** o **paso-a-paso**. Guárdalo en `.pipeline/modo` (una sola palabra).
- Guarda las variables de entorno que el proyecto necesitará en `.pipeline/variables-requeridas.txt` (solo nombres).

**Fase 1 reducida** (tarea sobre proyecto existente): plan de 5 a 15 líneas, criterios y riesgo. Riesgo bajo y medio: continúa sin esperar OK. Alto: espera OK.

## Fase 2: Desglose

Divide el trabajo en subtareas secuenciales del tamaño de un PR (menos de 400 líneas de diff como guía). Cada subtarea tiene id (T1, T2...), nombre, criterios de aceptación propios, interfaces que define (rutas, funciones, esquemas) y archivos esperados. Guarda el desglose en `.pipeline/plan.json` y los criterios de cada subtarea en `.pipeline/criterios-<id>.md`.

## Fase 3: Ciclo por subtarea

Por cada subtarea, en este orden:

1. **Auditoría del plan** (riesgo medio y alto; no aplica en el proceso ligero). Delega a `auditor` en modo plan con el plan y los criterios de la subtarea. Si devuelve `fail`, corrige el plan y repite. Máximo 2 vueltas; a la tercera, escala a Leonardo.
2. **Tests de aceptación.** Delega a `test-writer` con los criterios y las interfaces. Escribe tests en `tests/acceptance/` que fallen ahora. Commit aparte: `test(T1): criterios de aceptación`.
3. **Implementación.** Delega a `engineer` con el plan de la subtarea, los criterios, la ruta de los tests, el contenido de `LESSONS.md` (solo `LESSONS.md`, nunca las pendientes) y, si es reintento, los hallazgos del auditor. Rama `feat/T1-nombre`. El engineer trabaja en un worktree aislado (`isolation: worktree`) y una rama no puede estar activa en dos worktrees. Por eso, antes de delegar, crea y empuja la rama, y no la dejes activa en tu checkout: vuelve a `staging`. Pásale el nombre de la rama en el prompt; él hace `git switch <rama>` en su worktree y commitea ahí. Tú empujas después.
4. **Evidencia.** El engineer devuelve estado, rama, archivos, resumen de tests y resumen del diff. Guárdalo en `.pipeline/evidencia/T1.md`.
5. **Auditoría de código.** Delega a `auditor` en modo código con criterios, rama, evidencia y `LESSONS.md`. Guarda su JSON en `.pipeline/veredicto-T1.json`. Si trae `new_lesson`, agrégala a `.pipeline/lecciones-pendientes.md` con la subtarea y el archivo del veredicto, y el número del PR cuando lo abras. No la agregues a `LESSONS.md` (ver Memoria del sistema).
6. **Segundo auditor** (riesgo medio y alto, salvo en el proceso ligero de los PRs que solo tocan rutas de gobierno, que no lleva Codex ni JEV). Corre `/audit-codex T1`. Guarda en `.pipeline/veredicto-codex-T1.json`. Si Codex trae `new_lesson`, también va a `.pipeline/lecciones-pendientes.md`.
7. **Router.** En el proceso ligero no se ejecuta JEV: el PR se abre después de la ronda única, con el veredicto y lo que se corrigió o documentó en el cuerpo, y Leonardo decide al revisar. En los demás casos, ejecuta:
   `python scripts/jev.py --verdict .pipeline/veredicto-T1.json --attempt N --risk <nivel> [--codex .pipeline/veredicto-codex-T1.json] [--previous <veredicto anterior>]`
   Acuerdo: en riesgo medio y alto, Claude y Codex deben coincidir; si no, es HUMAN.
   y obedece la primera línea de la salida:
   - `PASS`: abre el PR contra `staging` con `gh pr create` usando la plantilla de abajo y comenta el veredicto en el PR.
   - `FIX`: vuelve al paso 3 con los hallazgos que JEV imprime, incluidos textualmente en el prompt del engineer. Incrementa `attempt`.
   - `HUMAN`: detente. Presenta a Leonardo qué falló, qué se intentó y qué recomiendas. Espera instrucción.
8. **Modo paso-a-paso**: pregunta a Leonardo antes de iniciar cada subtarea y antes de cada merge. **Modo automatico**: reporta al cerrar cada subtarea con el formato de reporte.

## Fase 4: Integración y deploy

- Los PRs los abre `talos-bot-leon`. PR sin rutas de gobierno: CI en verde y `PASS` → merge a `staging` con `gh pr merge <n> --squash`, siempre con el número del PR (el hook bloquea la forma sin número). PR con rutas de gobierno: lo aprueba y lo mergea Leonardo, también a `staging`; el servidor exige su aprobación como code owner y el hook bloquea tu merge. Railway despliega staging por su integración con GitHub; tú no corres `railway up`.
- Corre `/verificar-deploy staging`. Si falla: PR de revert a `staging` y `HUMAN`.
- Si staging pasa: abre (como `talos-bot-leon`) el PR de `staging` a `main` con el resumen de todas las subtareas, la evidencia y los veredictos. Leonardo lo aprueba y lo mergea él mismo desde GitHub (web o app); `main` exige una aprobación y la del code owner si hay rutas de gobierno. Tú nunca mergeas ni empujas a `main`; el hook lo bloquea.
- Tras el merge a `main`, corre `/verificar-deploy production`. Si falla: abre PR de revert a `main` y `HUMAN`.
- Reporte final: URLs, veredictos, intentos y tiempo por subtarea.

## Siempre requieren OK explícito de Leonardo

- Cualquier cosa que toque `main`.
- Cualquier comando `railway` que no sea de lectura.
- Migraciones de base de datos, staging incluido.
- Borrar datos, ramas, servicios o variables.
- Instalar una dependencia con licencia distinta de MIT, Apache o BSD.
- Gastar dinero: servicios nuevos, planes, APIs de pago.
- Mergear a `staging` un PR que modifique, borre o renombre alguna ruta listada en `.claude/rutas-gobierno.txt`: lo aprueba y lo mergea Leonardo. El servidor exige su aprobación como code owner (`.github/CODEOWNERS`) y el hook `guard-commands.sh` bloquea ese `gh pr merge`.

## Credenciales

- El token de `talos-bot-leon` vive en `~/.talos-gh/hosts.yml`, fuera del repo; el agente llega a él por `GH_CONFIG_DIR`, que definen `.claude/settings.local.json` (ignorado por git) y la plantilla `.claude/settings.local.example.json`. Ningún token vive en el repo ni en variables de entorno.
- Qué procesos pueden llegar a las credenciales: `gh` y `git` (por el helper `gh auth git-credential`) y cualquier proceso hijo de la sesión, incluido Codex, que hereda `GH_CONFIG_DIR` y podría leer el archivo si lo buscara. El hook bloquea los comandos que nombran tokens o esos archivos, los que imprimen credenciales o variables de entorno (`git credential fill|approve|reject` incluidos) y los que cambian de cuenta. También bloquea `git credential-manager`, salvo `github list`, porque toca el Credential Manager de Leonardo. `Read`, `Edit` y `Write` están denegados sobre `settings.local.json` y `~/.talos-gh`.
- La herramienta PowerShell está denegada en `.claude/settings.json`: el agente usa solo Bash, que es donde corren los hooks.
- Con `.claude/identidad-agente.txt` presente, el hook exige la identidad de `talos-bot-leon` para `git commit`, `git push`, los `gh pr` que escriben, `gh api` de escritura y los `gh repo` que escriben (`create`, `new`, `edit`, `rename`, `archive`, `unarchive`, `sync`). Si falta, bloquea en lugar de volver en silencio a la cuenta de Leonardo. Otros comandos de `gh` que escriben (`gh issue`, `gh run rerun`, `gh workflow run`, `gh release`) no se revisan; los límites conocidos están en el encabezado de `guard-commands.sh`.

## Prohibido sin excepción

- Leer o imprimir `.env`, tokens o secretos. Nombra la variable, nunca el valor.
- `git push --force` a cualquier rama.
- Que el engineer modifique `tests/acceptance/`, `CLAUDE.md`, `.claude/`, `docs/adr/` o `LESSONS.md`.
- Marcar una subtarea como terminada con tests en rojo.
- Cambiar este archivo o `.claude/` sin un PR aprobado por Leonardo.

## Formatos

### Veredicto del auditor (`.pipeline/veredicto-<id>.json`)

```json
{
  "task": "T1",
  "mode": "plan | code",
  "verdict": "pass | fail",
  "findings": [
    {"severity": "alta | media | baja", "file": "ruta", "detail": "qué y por qué", "fix": "cómo"}
  ],
  "tests_reviewed": true,
  "new_lesson": null
}
```

### Plantilla de PR

El cuerpo del PR va por `gh pr create --body-file <archivo>`, los comentarios por `gh pr comment --body-file <archivo>` y los mensajes de commit largos por `git commit -F <archivo>`, con el archivo escrito con la herramienta Write. Los títulos van sin flags ni nombres de variables. El hook revisa el texto de cada comando Bash y bloquea el que nombra tokens, archivos de credenciales o variables de identidad, aunque sea dentro de un `--title`, un `--body` o un `-m`. También bloquea el texto `gh repo create` (o `new`, `edit`, `fork`, `delete`, `deploy-key`), `gh api`, `gh alias` o `gh extension` dentro de un `--title`, un `-m` o un `-f body=`. Esos textos van con `--body-file`, `git commit -F` o `gh api -F body=@archivo`.

Título: `T1: nombre`
Cuerpo, en este orden:
- Objetivo
- Criterios de aceptación numerados, cada uno con ✓ o ✗ y la evidencia
- Tests: comando, resumen, cobertura si aplica
- Veredicto del auditor (JSON) y de Codex si aplica
- Riesgo y por qué
- Cómo hacer rollback

### Reporte a Leonardo (modo automatico)

Máximo 8 líneas: subtarea, resultado, intentos, hallazgos relevantes, siguiente paso, y si algo requiere su decisión.

## Memoria del sistema

- `docs/adr/`: una decisión por archivo. Lee los ADR existentes antes de proponer; no re-discutas lo ya decidido sin decirlo.
- `LESSONS.md`: una línea por patrón de error. Se incluye en cada delegación al engineer. Una lección entra al prompt del engineer solo cuando ya está en `LESSONS.md`: el engineer nunca recibe las pendientes.
- `.pipeline/lecciones-pendientes.md`: los `new_lesson` de los auditores, con su fuente. No es ruta de gobierno.
- **PR de lecciones.** `LESSONS.md` solo cambia con un PR de lecciones: uno solo al cierre de cada proyecto, o cuando haya 5 lecciones pendientes, lo que pase primero.
  - Lo abre `talos-bot-leon` con las pendientes propuestas, redactadas en el formato de `LESSONS.md`.
  - Leonardo las edita, descarta o acepta, y lo mergea él (es ruta de gobierno).
  - Las lecciones mergeadas o descartadas salen de pendientes en el mismo PR.
- `.pipeline/`: estado operativo (plan, criterios, evidencia, veredictos, modo). Se commitea.

## Modo no interactivo (Fase 2)

Si corres bajo `claude -p` (lanzado por `scripts/run-task.sh`) no hay nadie del otro lado del chat. Sigue el protocolo igual, y cuando llegues a una compuerta que requiere OK de Leonardo, termina tu turno con una última línea exacta:

`ESPERANDO OK: <qué necesitas que apruebe y las opciones>`

Nada después de esa línea. La sesión se reanudará con la respuesta de Leonardo.

## Estilo

Español. Sin guiones largos. Respuestas a Leonardo directas y sin preámbulo.
