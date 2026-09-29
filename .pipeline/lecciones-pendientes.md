# Lecciones pendientes

Aquí van los `new_lesson` de los auditores (Claude y Codex), textuales y con su fuente. No es ruta de gobierno: el CTO la actualiza en la rama de cada subtarea. El engineer nunca recibe este archivo; solo recibe `LESSONS.md`.

`LESSONS.md` cambia solo con un PR de lecciones: uno al cierre de cada proyecto, o cuando haya 5 lecciones pendientes, lo que pase primero.
- Lo abre `talos-bot-leon`, con las pendientes redactadas en el formato de `LESSONS.md` y agrupadas cuando repiten un patrón.
- Leonardo las edita, las descarta o las acepta, y lo mergea.
- En el mismo PR salen de aquí las que se mergearon o descartaron.

Formato: `- [fecha] [subtarea] patrón: qué evitar y qué hacer. (PR #n, archivo del veredicto)`. El texto del patrón es el del auditor. Si el original no trae el prefijo `[fecha] [subtarea]`, lo agrega el CTO.

## Pendientes

- [2026-09-28] [lecciones-1] PR de lecciones: descartar una pendiente porque 'ya está documentada en X' exige citar la línea de X que la cubre; si no existe, el patrón sale del repo sin rastro. El historial debe listar cada descartada con su veredicto de origen. (PR #14, `veredicto-lecciones-1.json`)
- [2026-09-28] [T3a] Una lista de permitidos que detecta el comando por la primera palabra del segmento tiene que saltar las palabras clave de shell (if, then, do, !, {) y los envoltorios comunes (timeout, xargs). Si no, retira sin avisar la cobertura que daba el grep textual al que reemplaza. (PR #15, `veredicto-T3a.json`)
- [2026-09-29] [T3b] Cuando el manifiesto de un instalador excluye archivos del repo fuente, comprobar que las suites copiadas (test-hooks.sh, CI) no lean esos archivos; si los leen, el repo instalado nace con checks obligatorios en rojo. (PR #16, `veredicto-T3b.json`)

## Historial

### 2026-09-28: antes del flujo de lecciones

Quedaron fuera las lecciones de los PRs #1 y #2 (hook-force-push y audit-codex-stdin). Leonardo decidió dejar en `LESSONS.md` solo las dos lecciones generales de esa época, y no llevar la de las citas.

### 2026-09-28: primer PR de lecciones (#14)

Criterio de Leonardo para este PR: proponer como máximo 5 lecciones generales para `LESSONS.md` y descartar las específicas del hook, que ya están documentadas en `guard-commands.sh`. Las líneas citadas son de `staging` en `ba8ed7c`.

**Condensadas en `LESSONS.md` (8 pendientes en 5 lecciones):**
- "documentar contra la herramienta real" viene de 3 pendientes:
  - #6, `veredicto-cuenta-agente-intento1.json` (docs de verificación);
  - #6, `veredicto-cuenta-agente-intento2.json`, segunda lección (docs de credenciales);
  - #11, `veredicto-vencimiento-token.json` (docs que afirman un control).
- "controles fail-closed": #6, `veredicto-codex-cuenta-agente-intento2.json`.
- "dos cuentas en una máquina" viene de 2 pendientes:
  - #6, `veredicto-cuenta-agente.json`, primera lección (login de una segunda cuenta);
  - #11, `veredicto-vencimiento-token-intento1.json` (prefijo del bot).
- "excepciones al protocolo": #13, `veredicto-lecciones.json`.
- "pruebas de reglas nuevas": #10, `veredicto-remoto-git-push.json`, segunda mitad. La primera mitad se descarta abajo.

**Descartadas por específicas del hook (8 pendientes, más la primera mitad de la de #10), con dónde quedan cubiertas en `guard-commands.sh`:**

| PR | Veredicto | Pendiente | Cobertura |
|---|---|---|---|
| #4 | `veredicto-hooks-windows-y-gobierno-intento1.json` | hook de compuerta: objetivo implícito | Línea 386 (número explícito) y el mensaje de la línea 489 |
| #4 | `veredicto-codex-hooks-windows-y-gobierno-intento1.json` | flags booleanos también con valor (`--flag=true`, `-f=true`) | Código, líneas 466 a 481 (`--admin=*`, `--delete-branch=*`, `grupo%%=*`), y los casos `-d=true` y `--delete-branch=true` de `test-hooks.sh`. Sin comentario propio |
| #4 | `veredicto-hooks-windows-y-gobierno.json` | matcher "Bash" y PowerShell | Líneas 395 y 396 |
| #4 | `veredicto-codex-hooks-windows-y-gobierno.json` | número de PR y `cd`/`pushd` | Líneas 393 y 394 |
| #6 | `veredicto-codex-cuenta-agente-intento1.json` | análisis por segmento y opciones globales | Líneas 276 y 277, y la definición de `F` (líneas 61 a 64) |
| #6 | `veredicto-cuenta-agente-intento2.json`, primera lección | excepción por flag solo fuera de comillas | Línea 293 |
| #6 | `veredicto-cuenta-agente.json`, segunda lección, y `veredicto-codex-cuenta-agente.json` | argumentos del subcomando: redirecciones, comillas y opciones con valor | Bloque del remoto de `git push`, líneas 318 a 377 |
| #10 | `veredicto-remoto-git-push.json`, primera mitad | `(` y `)` pegados a los tokens | Línea 338 |
