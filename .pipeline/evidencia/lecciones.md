# Evidencia: lecciones (T2)

- **Estado:** listo para la ronda del auditor Claude. Proceso ligero, excepción aprobada por Leonardo: una ronda, sin Codex ni JEV.
- **Rama:** `feat/T2-lecciones`, desde `staging` en `713de65` (con el #12). Con `identidad-agente.txt` activo, el push de la rama pasó como `talos-bot-leon`: fue la verificación final del paso g.
- **Implementó:** el CTO, pruebas e implementación, por la regla de rutas de gobierno. Commits como `talos-bot-leon`.
- **Riesgo:** medio.

## Commits

1. `3ff4578` test(lecciones). Agrega:
   - 14 casos de credenciales que bloquean (11 de `git credential-manager` y 3 de `git credential fill|approve|reject`);
   - 2 casos permitidos de `github list`;
   - 10 chequeos de protocolo (texto de `CLAUDE.md` y de los dos prompts de auditor, existencia de las pendientes, `.pipeline/` fuera de gobierno).
2. `4406e58` feat(lecciones). Implementación: el hook, `CLAUDE.md`, `auditor.md`, `auditor-codex.md`, `.pipeline/lecciones-pendientes.md` y `SETUP.md`.

## Criterios

- **C1.** `.pipeline/lecciones-pendientes.md` trae 15 lecciones, generadas con jq desde el `new_lesson` de cada veredicto: 4 del #4, 8 del #6 y 3 de #10 y #11. Cada una lleva el PR y el archivo del veredicto. No incluye las de #1 y #2.
- **C2.** `CLAUDE.md`:
  - tabla de roles (engineer: "nunca las lecciones pendientes");
  - Fase 3, paso 3 ("solo `LESSONS.md`, nunca las pendientes") y paso 5 ("agrégala a `.pipeline/lecciones-pendientes.md`");
  - Memoria del sistema: `LESSONS.md` y pendientes, y el PR de lecciones (al cierre del proyecto o con 5 pendientes, lo abre `talos-bot-leon`, lo mergea Leonardo, y las lecciones mergeadas o descartadas salen de pendientes).
- **C3.** `auditor.md` (Severidad y `new_lesson`) y `auditor-codex.md` (Severidad): el párrafo del modelo de amenaza.
- **C4.** `CLAUDE.md`:
  - "Cambios en rutas de gobierno" con los cuatro controles, donde la mutación va si hay código o pruebas;
  - "Proceso ligero para PRs que solo tocan rutas de gobierno", con la verificación de `require_code_owner_reviews`, `.pipeline/` fuera de la cuenta, una sola ronda, el protocolo completo si la protección no está activa y las apps siempre con el protocolo completo;
  - Fase 3, paso 6, con la excepción.
- **C5.** `guard-commands.sh`: el patrón `gcm` (git con opciones globales antes de `credential-manager`, o `git-credential-manager`, con `.exe` opcional). Se revisa por segmento, y solo pasa `credential-manager github list` con sus argumentos. La prueba rápida sobre una copia del hook dio 13 de 13.
- **C6.** `CLAUDE.md` (Credenciales), `SETUP.md` (nota del remedio del paso c) y el encabezado del hook.
- **C7.** Suite y mutación: ver Tests.

## Tests

- **Comando:** `bash scripts/test-hooks.sh`.
- **Resultado:** `455 ok, 0 fallos` (Git Bash, gawk). Salida completa en `.pipeline/test-hooks-salida.txt`.
- **Mutación contra `staging`:** la suite de la rama contra los hooks, las reglas, los settings, el CI, la plantilla, `CLAUDE.md` y los prompts de auditor de `staging`. Resultado: `435 ok, 20 fallos`, exit 1.
  - Fallan los 11 bloqueos nuevos de `git credential-manager` y los 9 chequeos de protocolo.
  - Los otros casos nuevos ya se cumplían en `staging`: las variantes de `fill|approve|reject`, los dos `github list` permitidos y `.pipeline/` fuera de gobierno.
- **En vivo:** con el hook nuevo en la copia de trabajo, un `sed` del CTO cuyo texto decía "git credential-manager" quedó bloqueado. Es el límite documentado en el hook (el texto cuenta aunque sea dentro de otro comando).
