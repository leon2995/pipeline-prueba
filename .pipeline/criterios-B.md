# Criterios: B (instalador para repos de la organización)

Riesgo: **medio**. El instalador arma el contenido del PR T0 de cada repo nuevo de la organización, y con este cambio también genera la identidad obligatoria del agente. No toca GitHub ni Railway, no agrega dependencias y sigue escribiendo solo archivos locales.

Va con el proceso ligero de este plan, la excepción al congelamiento que aprobó Leonardo el 2026-09-29: una ronda del auditor Claude, sin Codex ni JEV. El instalador y sus pruebas van con el protocolo normal: test-writer en `tests/acceptance/` y engineer en `instalador/` y `tests/unit/`. Lo que toca rutas de gobierno lo hace el CTO. Como el PR toca rutas de gobierno, lo mergea Leonardo.

Plan aprobado: A1 (#19), A1b (#20) y A2 (#21) ya están en `staging`. B completa lo que dejó escrito A2 en `.pipeline/criterios-A2.md` ("Fuera de alcance (B)"), que es el contrato con el paso 0 de `/crear-repo`. Hasta B, ese paso corta solo.

## Plan

1. **test-writer:** actualiza `tests/acceptance/test-instalador.sh` para los criterios de abajo. Las pruebas que cambian fallan hasta la implementación.
2. **CTO (rutas de gobierno):**
   - invierte en `scripts/test-hooks.sh` el chequeo "el paso 0 de /crear-repo corta con el instalador actual", que pasa a exigir que no corte;
   - ajusta en `.claude/commands/crear-repo.md` los pasos 7 y 9 a la salida nueva.
3. **engineer:** en su worktree y en la rama `feat/B-instalador-org`, cambia `instalador/instalar.sh`, `instalador/plantillas/` y `instalador/manifiesto.txt` (solo comentarios), con pruebas unitarias en `tests/unit/test-instalar.sh`.
4. **Auditor Claude:** una ronda. Después, el PR contra `staging`.

## Interfaces

- **La invocación no cambia:** `bash instalador/instalar.sh <destino> [--aplicar] [--modo nuevo|existente] [--servicio NOMBRE] [--puerto N]`, con los mismos códigos de salida (0, 2 y 3).
- **La organización:** sale de `org` en `.claude/pipeline.conf` de la fuente. Si falta o no es válida, es un error de fuente, como hoy con `bot` o `dueno`.
- **Repo de la organización:** el dueño del `origin` de GitHub coincide con `org`, sin distinguir mayúsculas.
- **Salida:**
  - `rama staging: existe` si hay una rama local `staging` o `origin/staging`, y `rama staging: no se crea` en cualquier otro caso. Desaparecen `crear` y `sin commits`.
  - Una nota nueva: `nota: el destino no es un repo de <org>: ...`.
  - `crear|igual|conflicto .claude/identidad-agente.txt`, como cualquier otro archivo generado.

## Criterios

- **B1. Identidad del agente.** El instalador genera `.claude/identidad-agente.txt` con una sola línea, el `bot` de `pipeline.conf`.
  - Es un archivo generado: se crea si no existe, y si existe cuenta como `igual` o `conflicto`.
  - No cuenta para detectar el modo.
  - El manifiesto no lo lista: lo genera el instalador, no lo copia.
- **B2. `staging` no se crea en local.** Con `--aplicar` o sin él, el instalador no crea, no mueve y no borra ninguna rama. En un repo nuevo, `staging` nace en el servidor desde `main`, después del PR T0 (paso 9 de `/crear-repo`).
  - Si `staging` existe (local o solo como `origin/staging`), la salida es `rama staging: existe`, y el caso de solo `origin/staging` mantiene su nota de hoy.
  - En los demás casos, la salida es `rama staging: no se crea`.
  - Sigue sin hacer commit, push ni fetch.
- **B3. Repo de la organización, sin notas.** En un repo cuyo `origin` es `https://github.com/<org>/<repo>.git` y que no tiene `staging` (el caso del paso 0 y del paso 5 de `/crear-repo`), la salida no trae ninguna línea `nota:`.
  - La nota del dueño ya no sale para estos repos: el code owner sigue siendo `dueno=` aunque el dueño del `origin` sea la organización.
- **B4. Fuera de la organización.** Si el `origin` no es de `<org>`, o no hay `origin`, sale la nota `el destino no es un repo de <org>: el framework se instala, pero la protección de ramas la dan los rulesets de la organización y aquí no aplican (CLAUDE.md, Repos en la organización).` Las notas de hoy (sin origin, origin que no es de GitHub, dueño distinto de `dueno=`) siguen saliendo.
- **B5. Pasos manuales.** Después de `== Pasos manuales` salen solo las secciones que le tocan a Leonardo, en este orden, con los marcadores reemplazados:
  1. **Agente:** copiar `.claude/settings.local.example.json` como `.claude/settings.local.json` si no existe, completar `GH_CONFIG_DIR` y reiniciar la sesión. Una línea dice que `.claude/identidad-agente.txt` ya viene en el PR T0 y que, desde la primera sesión, el hook exige la identidad del bot.
  2. **Railway, cuando `staging` ya exista:**
     - los mismos comandos de hoy;
     - una línea que diga que la GitHub App de Railway tiene que tener acceso al repo (All repositories en `<org>`);
     - una que diga que el `package.json` de `npm install --save-dev railway@3.11.0` entra por PR desde la sesión del repo.

  Desaparecen la sección de Git (commit, `staging`, push) y la de GitHub (invitación del bot y protección por repo). La primera línea de los pasos dice que el git, el PR T0 y la creación de `staging` los hace el agente con `/crear-repo`, y que la protección la dan los rulesets de la organización. Los conflictos siguen saliendo con su comando `diff` antes de las secciones. Ningún paso imprime ni pide un token.
- **B6. Contrato con el paso 0 de `/crear-repo`.** Sobre un repo con `origin` `https://github.com/<org>/<nombre>.git` y un commit vacío, la simulación (sin `--aplicar`) tiene la línea `crear .claude/identidad-agente.txt`, no tiene la línea `rama staging: crear` y no tiene ninguna línea que empiece con `nota:`.
  - En `scripts/test-hooks.sh`, el chequeo del paso 0 queda así: "el paso 0 de /crear-repo pasa con el instalador actual".
- **B7. `/crear-repo` con la salida nueva.** El paso 7 lleva en el cuerpo del PR T0 la lista de archivos y la sección Agente de los pasos. El paso 9 remite a la sección Railway. Ya no menciona las secciones 1 y 2.
- **B8. Lo que no cambia sigue igual.** Lo cubren las pruebas de T3b:
  - la simulación por defecto;
  - qué se copia y qué nunca;
  - no pisar archivos;
  - los otros archivos generados;
  - la detección de modo;
  - los errores de uso;
  - la portabilidad (Git Bash y Linux, rutas con espacios, sin extensiones de gawk);
  - que nunca llame a `gh` ni a `railway`.
- **B9. Suites.**
  - `npm test` (aceptación y unitarias) da 0 fallos en Windows y en CI;
  - `bash scripts/test-hooks.sh` da 0 fallos con gawk y con mawk, en CI y en Windows;
  - las pruebas de aceptación nuevas fallan con el instalador de `staging` antes de la implementación.

## Fuera de alcance

- Migrar un repo existente a la organización (transferencia).
- Automatizar Railway.
- El repo de prueba `prueba-rulesets` y el primer proyecto real, que van después de B con `main` actualizado.
