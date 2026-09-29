# Criterios: lecciones (T2)

Riesgo: **medio**. Cambia el protocolo en `CLAUDE.md`, los dos prompts de auditor y el hook de comandos. Todo es ruta de gobierno: lo implementa el CTO (pruebas primero y mutación contra `staging`), lo abre `talos-bot-leon`, y lo aprueba y mergea Leonardo como code owner.

**Proceso ligero, excepción aprobada por Leonardo** para el PR corto, T2 y T3: una ronda del auditor Claude, sin Codex ni JEV. Su razón: con la protección de code owners activa, ningún cambio de gobierno entra sin su aprobación. T2 convierte la regla en permanente (C4).

**Modelo de amenaza del cambio en el hook (C5): errores del agente, no ofuscación deliberada.** El bloqueo frena que el agente, por costumbre o por seguir una instrucción de `SETUP.md`, toque el Credential Manager de Leonardo o lea una credencial guardada. No cubre formas deliberadas de esconder el comando (variables, `bash -c`, aliases), igual que el resto del hook.

## Plan

1. Pruebas primero, en un commit aparte:
   - casos en `scripts/test-hooks.sh` para `git credential-manager` y para `git credential fill|approve|reject`;
   - chequeos de texto de `CLAUDE.md` y de los dos prompts de auditor.

   Contra `staging`, los casos de bloqueo nuevos y los chequeos de texto fallan.
2. `guard-commands.sh`: bloqueo de `git credential-manager` y `git-credential-manager`, salvo `github list`, en la sección de credenciales.
3. `CLAUDE.md`:
   - flujo de lecciones (Fase 3, paso 5; Memoria del sistema);
   - regla permanente del proceso ligero (Cambios en rutas de gobierno y Fase 3);
   - sección Credenciales.
4. `.claude/agents/auditor.md` y `.claude/prompts/auditor-codex.md`: evasiones fuera del modelo de amenaza con severidad baja; `new_lesson` va a pendientes.
5. `.pipeline/lecciones-pendientes.md`, con las lecciones candidatas.
6. `SETUP.md`: la nota del remedio del paso c dice que el hook ahora bloquea `git credential-manager`.
7. Suite local, mutación, evidencia, una ronda del auditor Claude y PR contra `staging` como `talos-bot-leon`.

## Criterios

- **C1. Lecciones pendientes.** Existe `.pipeline/lecciones-pendientes.md`, fuera de las rutas de gobierno. Su encabezado explica el flujo y lista, textuales y con su fuente (PR y archivo de veredicto):
  - las lecciones candidatas de los PRs #4 y #6;
  - las de los PRs posteriores (#10 y #11), que siguen la regla nueva.

  No incluye las de los PRs #1 y #2, que Leonardo decidió no llevar a `LESSONS.md`.
- **C2. Flujo en `CLAUDE.md`.**
  - En la Fase 3, paso 5, el `new_lesson` del auditor se agrega a `.pipeline/lecciones-pendientes.md`, no a `LESSONS.md`.
  - `LESSONS.md` solo cambia con un PR de lecciones: uno solo al cierre de cada proyecto, o cuando haya 5 lecciones pendientes, lo que pase primero. Lo abre `talos-bot-leon` y lo mergea Leonardo; las lecciones mergeadas salen de pendientes.
  - Una lección entra al prompt del engineer solo cuando ya está en `LESSONS.md`: el engineer recibe `LESSONS.md` y nunca las pendientes. Esto queda en la tabla de roles, en la Fase 3 (paso 3) y en Memoria del sistema.
- **C3. Modelo de amenaza en los auditores.** `.claude/agents/auditor.md` y `.claude/prompts/auditor-codex.md` dicen, en la sección de severidad, que si los criterios declaran un modelo de amenaza, las evasiones que quedan fuera de él se reportan con severidad baja y no causan `fail`. El `new_lesson` de `auditor.md` apunta a pendientes, no a `LESSONS.md`.
- **C4. Regla permanente del proceso ligero.** `CLAUDE.md` dice:
  - Los PRs que solo tocan rutas de gobierno van con una ronda del auditor Claude y la aprobación de Leonardo como code owner, sin Codex ni JEV, siempre que la protección con code owners esté activa en `staging` y `main`. El CTO la verifica con `gh api` antes de aplicar la regla. Los archivos de `.pipeline/` (estado operativo) no cuentan como ruta fuera de gobierno.
  - Es una sola ronda: los hallazgos se corrigen o se documentan en el PR, y Leonardo decide al revisar.
  - Si la protección no está activa, va el protocolo completo.
  - Los PRs de código de apps siguen con el protocolo completo.

  El párrafo "Cambios en rutas de gobierno" queda coherente: pruebas primero, mutación contra `staging` cuando hay código o pruebas, auditor según la regla, y aprobación de Leonardo.
- **C5. `git credential-manager`.** El hook bloquea, con motivo "credenciales", `git credential-manager` y `git-credential-manager` (también con `.exe` y con opciones globales de git antes), en cualquier segmento, salvo `github list` y sus opciones. Casos en la suite:
  - **Bloquean:** `github logout`, `github login --username x --device`, `get`, `store`, `erase`, `configure`, la invocación sin subcomando, `git-credential-manager github logout x`, `git -C . credential-manager github logout x`, y `github list` seguido de `; git credential-manager github logout x`.
  - **Pasan:** `git credential-manager github list` y `git credential-manager github list --url https://github.com`.
  - `git credential fill`, `approve` y `reject` siguen bloqueados, con casos para cada uno: `fill` por una tubería y `fill` con opciones globales antes.
- **C6. Coherencia.** La sección Credenciales de `CLAUDE.md` y la nota del remedio del paso c de `SETUP.md` dicen que el hook bloquea `git credential-manager` (salvo `github list`). El encabezado del hook lo documenta.
- **C7. Sin regresiones.** El resto de la suite sigue pasando, en local y en CI con gawk y con mawk. La mutación contra `staging` falla en los casos nuevos de bloqueo y en los chequeos de texto.

Verificación posterior al PASS: el PR queda bloqueado hasta la aprobación de Leonardo como code owner. Como las pendientes ya pasan de 5, el primer PR de lecciones va justo después de T2.
