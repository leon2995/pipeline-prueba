# Lecciones pendientes

Aquí van los `new_lesson` de los auditores (Claude y Codex), textuales y con su fuente. No es ruta de gobierno: el CTO la actualiza en la rama de cada subtarea. El engineer nunca recibe este archivo; solo recibe `LESSONS.md`.

`LESSONS.md` cambia solo con un PR de lecciones: uno al cierre de cada proyecto, o cuando haya 5 lecciones pendientes, lo que pase primero.
- Lo abre `talos-bot-leon`, con las pendientes redactadas en el formato de `LESSONS.md` y agrupadas cuando repiten un patrón.
- Leonardo las edita, las descarta o las acepta, y lo mergea.
- En el mismo PR salen de aquí las que se mergearon o descartaron.

Formato: `- [fecha] [subtarea] patrón: qué evitar y qué hacer. (PR #n, archivo del veredicto)`. El texto del patrón es el del auditor. Si el original no trae el prefijo `[fecha] [subtarea]`, lo agrega el CTO; por ejemplo, la segunda lección del PR #4.

Quedan fuera las lecciones de los PRs #1 y #2 (hook-force-push y audit-codex-stdin): Leonardo decidió dejar en `LESSONS.md` solo las dos lecciones generales de esa época, y no llevar la de las citas.

## Pendientes

### PR #4: hooks-windows-y-gobierno

- [2026-09-28] [hooks-windows-y-gobierno] hooks de compuerta: un hook que resuelve el objetivo de forma implícita (PR de la rama actual, cwd) evalúa el estado del momento del hook y no el del comando encadenado (git switch x && gh pr merge); exigir identificador explícito y probar el comando con redirecciones comunes (2>&1, >log). (PR #4, `veredicto-hooks-windows-y-gobierno-intento1.json`)
- [2026-09-28] [hooks-windows-y-gobierno] Los hooks que bloquean flags booleanos deben cubrir y probar también sus formas estándar con valor, como `--flag=true` y `-f=true`. (PR #4, `veredicto-codex-hooks-windows-y-gobierno-intento1.json`)
- [2026-09-28] [hooks-windows-y-gobierno] hooks en Windows: un PreToolUse con matcher "Bash" no cubre la herramienta PowerShell, que en Windows es el shell principal de la sesión; los controles de comandos deben usar matcher "Bash|PowerShell" o declarar el límite. (PR #4, `veredicto-hooks-windows-y-gobierno.json`)
- [2026-09-28] [hooks-windows-y-gobierno] contexto de repositorio: un número de PR es relativo al repositorio; si el comando puede ejecutar `cd` o `pushd` antes del merge, el hook puede auditar otro PR. Exigir contexto inmutable o consultar explícitamente el repositorio efectivo y probar comandos compuestos. (PR #4, `veredicto-codex-hooks-windows-y-gobierno.json`)

### PR #6: cuenta-agente (T1)

- [2026-09-28] [cuenta-agente] docs de verificación: cuando se documenta un comando de verificación con su salida esperada, confirmar que lee la misma clave que se configuró (credential.<url>.helper no aparece en `git config --get-all credential.helper`); usar --get-regexp o --get-urlmatch. (PR #6, `veredicto-cuenta-agente-intento1.json`)
- [2026-09-28] [cuenta-agente] hooks de comandos: analizar cada invocación y sus opciones globales por segmento; un flag inocuo en otro segmento o una opción global no debe borrar una escritura ya detectada. (PR #6, `veredicto-codex-cuenta-agente-intento1.json`)
- [2026-09-28] [cuenta-agente] hooks de comandos: una excepción por flag (--help, -X GET) se reconoce solo como token fuera de comillas; un --help dentro de un --title o --body no es una invocación con --help. (PR #6, `veredicto-cuenta-agente-intento2.json`)
- [2026-09-28] [cuenta-agente] docs de credenciales: antes de fijar scopes o un comando de verificación en criterios o SETUP, confirmar que la herramienta los acepta (gh auth login exige repo y read:org en un token classic) y que el comando corre donde existen las variables que verifica (el env de settings.local.json solo existe dentro de la sesión). (PR #6, `veredicto-cuenta-agente-intento2.json`)
- [2026-09-28] [cuenta-agente] identidad fail-closed: verificar la ruta de credenciales que usará la operación protegida; comprobar otra CLI o solo la presencia de variables permite que las pruebas pasen con una configuración inválida o con credenciales de otra cuenta. (PR #6, `veredicto-codex-cuenta-agente-intento2.json`)
- [2026-09-28] [cuenta-agente] docs de login de una segunda cuenta con gh: con --git-protocol https, gh auth login pregunta "Authenticate Git with your GitHub credentials?" (Sí por defecto). Si ya hay otro helper, como GCM, corre git credential reject/approve y cambia la credencial de git de la cuenta principal por la nueva. Hay que indicar la respuesta No y verificar después el helper del sistema. (PR #6, `veredicto-cuenta-agente.json`)
- [2026-09-28] [cuenta-agente] hooks de comandos: para leer los argumentos de un subcomando (el remoto de git push), ubicar la invocación real y quitar antes las redirecciones y el texto entre comillas; si se toma el primer token después de cualquier palabra 'push', el remoto sale de un '2>' o de un --title. (PR #6, `veredicto-cuenta-agente.json`)
- [2026-09-28] [cuenta-agente] analizadores de comandos: no reconstruir argumentos con split por espacios ni asumir que todo token no iniciado por guion es posicional; probar espacios equivalentes, valores entre comillas y opciones que consumen argumentos. (PR #6, `veredicto-codex-cuenta-agente.json`)

### PRs posteriores, con la regla nueva

- [2026-09-28] [remoto-git-push] tokenizar shell: al partir segmentos con xargs o set --, los delimitadores de subshell '(' y ')' quedan pegados a los tokens; normalízalos antes de comparar subcomandos, y prueba cada rama nueva de una máquina de estados con al menos un caso que deba pasar. (PR #10, `veredicto-remoto-git-push.json`)
- [2026-09-28] [vencimiento-token] docs de dos cuentas: cada comando gh o git que se refiere a la cuenta del agente, incluidas las menciones en prosa, debe llevar completo el prefijo de configuración del bot; sin él se ejecuta con la cuenta humana. (PR #11, `veredicto-vencimiento-token-intento1.json`)
- [2026-09-28] [vencimiento-token] docs que afirman un control: si un documento dice que un hook bloquea un comando, verificarlo contra el regex del hook antes de escribirlo; si no, el documento promete una protección que no existe. (PR #11, `veredicto-vencimiento-token.json`)
- [2026-09-28] [lecciones] protocolo con excepciones: al agregar una excepción a un paso (sin Codex, sin JEV), actualizar todas las compuertas que imponen ese paso (niveles de riesgo en Fase 0, router, auditoría del plan) y no solo el párrafo nuevo y el paso más cercano; si no, quedan dos reglas contradictorias sin precedencia. (PR de T2, `veredicto-lecciones.json`)
