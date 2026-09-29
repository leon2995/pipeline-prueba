# Criterios: instalable (PR de gobierno corto antes del primer proyecto real)

Riesgo: **bajo**. Dos cambios en rutas de gobierno que salieron de la auditoría de T3b (PR #16), más la actualización de C5 de T3b, que pidió Leonardo. Va con el proceso ligero: una ronda del auditor Claude y la aprobación de Leonardo como code owner. Lo implementa el CTO, con las pruebas primero.

- **C1. `SETUP.md` opcional en la suite.**
  - `scripts/test-hooks.sh` corre el chequeo del texto de `SETUP.md` (el remedio del paso c) solo si el archivo existe. Si no existe, imprime una línea `omitido: no hay SETUP.md (repo instalado)` y no suma un fallo.
  - Con `SETUP.md` presente, el chequeo sigue igual.
  - Evidencia: la suite corre sobre una copia del repo sin `SETUP.md` sin fallos por ese chequeo, y en este repo el total no cambia.
- **C2. Tiempo del hook Stop.**
  - El hook Stop de `.claude/agents/engineer.md` (`run-tests.sh`) declara `timeout: 600`.
  - Un chequeo de la suite lo verifica.
- **C3. C5 de T3b.** `.pipeline/criterios-T3b.md` describe la detección de modo que Leonardo aceptó: se ignoran las rutas del manifiesto y las generadas por el instalador. Por eso una corrida sobre un repo que ya tiene el framework commiteado sigue en `modo nuevo`.
- **C4. Sin regresiones.** La suite pasa en local y en CI, con gawk y con mawk.
