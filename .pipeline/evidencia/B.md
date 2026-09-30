# Evidencia: B

- **Estado:** auditado, con el proceso ligero de este plan: una ronda del auditor Claude, sin Codex ni JEV.
  - **Veredicto:** `pass`, con 1 media y 5 bajas (`.pipeline/veredicto-B.json`).
  - **La media:** la evidencia en Windows de `test-hooks.sh`. Se cierra con la corrida de abajo.
  - **Corregidas después de la ronda:**
    - el cuerpo del PR T0 va sin la ruta de la configuración de gh del bot (paso 7 de `crear-repo.md`);
    - la suite suma un control negativo del paso 0 (un repo fuera de la organización corta) y los chequeos de que el paso 9 remite a la sección Railway y de que ya no nombra las secciones 1 y 2.
  - **Documentadas en el PR:**
    - la prueba `b5_no_pide_identidad_por_pr` es más estricta que el criterio (nota 1 del engineer);
    - el encabezado de los pasos supone `/crear-repo` también fuera de la organización;
    - la app de Railway con All repositories, frente a Only select repositories.
  - **La lección nueva** va a pendientes, que quedan en 8, hasta el cierre de B.
- **Verificación previa, con un workflow de 2 agentes:** uno simuló `/crear-repo` de punta a punta sin GitHub y otro revisó el diff con ojo adversarial. Dejó 24 verificaciones correctas y 8 bajas. La simulación salió bien en todo:
  - el paso 0 cumple sus tres condiciones;
  - el repo con README en `feat/T0-framework` se detecta como `modo nuevo`, sin conflictos;
  - `identidad-agente.txt` sale con 15 bytes (`talos-bot-leon` y un salto);
  - no se crea ninguna rama y no hay notas;
  - los pasos tienen solo encabezado, Agente y Railway;
  - no queda ningún marcador;
  - la segunda corrida sale toda `igual`;
  - con `staging` en el remoto dice `existe`, y fuera de la organización sale la nota B4.

  Lo que se hizo con las bajas:
  - **Corregida:** el paso 8 guarda la sección Railway del paso 5 y el paso 9 se la pasa a Leonardo. Antes, ningún paso se la entregaba.
  - **Documentadas:**
    - la prueba unitaria del orden de los conflictos solo fija que van antes de la sección Agente, no después del encabezado;
    - `preparar_pasos` reemplaza `gh_config_dir` antes que `destino`, y un `HOME` con `{{destino}}` o un destino con `{{conflictos}}` y un salto de línea alterarían la salida (casos rebuscados);
    - el encabezado y la línea de la app de Railway suponen un repo de la organización, también fuera de ella;
    - la suite del repo instalado no se corrió completa en local: tarda más de 30 minutos. Se verificó en forma estática que solo `SETUP.md` e `instalador/` faltan, y que los dos van detrás de guardas `[ -f ]`.
- **Rama:** `feat/B-instalador-org`, desde `staging` en `b016fd9` (A2, #21).
- **Implementaron:**
  - el test-writer, las pruebas de aceptación;
  - el CTO, las rutas de gobierno (`scripts/test-hooks.sh`, `.claude/commands/crear-repo.md` y `CLAUDE.md`);
  - el engineer, el instalador y las pruebas unitarias.

  Todos los commits salen como `talos-bot-leon`.
- **Riesgo:** medio.
- **Intentos del engineer:** 1, con estado DONE. Es la primera subtarea con el engineer en Sonnet 5.5 (`claude-sonnet-5-5`, `effort: xhigh`). Queda anotado para la revisión de modelos de CLAUDE.md.

## Commits

1. `d53e38e` test(B): criterios (`.pipeline/criterios-B.md`) y, en `scripts/test-hooks.sh`, el chequeo del paso 0 de `/crear-repo` invertido y la frase nueva de `crear-repo.md`.
2. `142a254` test(B): pruebas de aceptación del test-writer para B1 a B6 y B8.
3. `9d8b8a2` B: `crear-repo.md` y `CLAUDE.md` con la salida nueva del instalador (B7).
4. `f512847` feat(B): el instalador genera la identidad del agente y no crea ramas (engineer).
5. `40c0692` test(B): pruebas unitarias del instalador para repos de la organización (engineer).

## Tests

- **Pruebas primero, en CI (Linux), sobre `142a254`, con el instalador de `staging`:**
  - la aceptación dio `50 ok, 44 fallos`. Los 44 son las conductas de B1 a B6: no hay identidad, sale `rama staging: crear`, sale la nota del dueño, falta la nota de fuera de la organización, salen los pasos de `git commit` y protección, y el paso 0 no se cumple;
  - `test-hooks.sh` dio `1048 ok, 2 fallos`: los dos chequeos invertidos de B6 y B7.
  - La primera corrida local del test-writer no sirvió como medida: el disco C: estaba lleno. Por eso la validación se hizo en CI.
- **Engineer, en Windows:** `bash tests/acceptance/test-instalador.sh` da `94 ok, 0 fallos`, y `bash tests/unit/test-instalar.sh` da `155 ok, 0 fallos`.
- **CI del push en `40c0692`:** pendiente.
- **Suite de hooks completa en Windows sobre `40c0692`:** en curso.

## Notas del engineer

1. **La identidad va en dos líneas.** La prueba de aceptación `b5_no_pide_identidad_por_pr` prohíbe una línea que tenga `identidad-agente` y la palabra `PR`. Por eso la mención quedó en dos líneas seguidas: "ya viene incluido, con una sola línea: `<bot>`" y "Va en el PR T0 y, desde la primera sesión, el hook exige la identidad".
2. **Igualdad estricta de la identidad.** Si el archivo no tiene salto final, cuenta como conflicto; con CRLF cuenta como igual. Es la misma regla de los demás generados, y el hook lee la identidad con `tr -d '[:space:]'`.
3. **La línea `cd '<destino>'`** queda antes de los conflictos, porque la sección Agente usa rutas relativas.
4. **El texto de la GitHub App de Railway** no nombra la ruta del menú.
5. **La nota del dueño**, para repos fuera de la organización, termina en "antes de commitear el framework", porque el paso 1 ya no existe.
