# Evidencia: instalable

- **Estado:** listo para la ronda del auditor Claude. Proceso ligero: una sola ronda, sin Codex ni JEV.
- **Rama:** `fix/instalable`, desde `staging` en `5ddfbf1` (con T3b).
- **Implementó:** el CTO, con las pruebas primero. Commits como `talos-bot-leon`.
- **Riesgo:** bajo.

## Commits

1. `c645312` test(instalable): el chequeo `engineer.md: el hook Stop declara timeout: 600`, que lee la línea `timeout:` que sigue a `run-tests.sh`, y los criterios.
2. Implementación:
   - `scripts/test-hooks.sh` corre el chequeo de `SETUP.md` solo si el archivo existe; si no, imprime `omitido: no hay SETUP.md (repo instalado)`;
   - `.claude/agents/engineer.md` agrega `timeout: 600` al hook Stop;
   - `.pipeline/criterios-T3b.md` actualiza C5 con la detección de modo que Leonardo aceptó.

## Criterios

- **C1.** Suite en una copia del repo sin `SETUP.md`: la copia se armó con `git archive` más los archivos de esta rama y es un repo git con `origin` HTTPS, como en CI. Da `636 ok, 0 fallos` y muestra la línea `omitido: no hay SETUP.md (repo instalado)`. En la rama, con `SETUP.md`, da `637 ok, 0 fallos`: son los 636 más el chequeo de `SETUP.md`. Antes de este cambio, la suite de `staging` fallaba en ese chequeo cuando falta `SETUP.md`: lo mostró la mutación de T3a, que no copiaba `SETUP.md`.
- **C2.** `engineer.md` tiene `timeout: 600` bajo el comando de `run-tests.sh`. El chequeo nuevo falla con el `engineer.md` de `origin/staging` y con el del commit de pruebas, y pasa con el de la implementación.
- **C3.** C5 de `criterios-T3b.md` describe la detección de modo que se aceptó, con la nota del cambio.
- **C4.** Ver C1. El CI del push corre la suite con gawk y con mawk.
