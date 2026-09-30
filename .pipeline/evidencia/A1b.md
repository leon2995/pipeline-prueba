# Evidencia: A1b

- **Estado:** auditado. Proceso ligero, una sola ronda del auditor Claude. Veredicto `fail`, con 1 alta y 3 bajas, en `.pipeline/veredicto-A1b.json`.
  - **La alta:** era la evidencia pendiente (la suite en Windows y el CI). Queda cerrada abajo.
  - **Las tres bajas:** están corregidas, con los casos primero: `CDPATH` y `--` en el `cd`, el mismo patrón en C4, y los casos con un espacio en la ruta y con `CDPATH`.
- **Rama:** `fix/A1-staging-windows`, desde `staging` en `9ce952e` (A1, #19).
- **Implementó:** el CTO, porque es ruta de gobierno. Commits como `talos-bot-leon`.
- **Riesgo:** medio.

## Origen

La suite completa en Windows (Git Bash) sobre `staging` en `9ce952e` se cortó en la línea 829 de unas 990, por el límite de tiempo de la herramienta. Hasta ahí dio 3 fallos, todos casos permitidos de C7 de A1:
- `git -C /tmp/.../con-codeowners push origin origin/main:refs/heads/staging`;
- lo mismo con `:staging`;
- lo mismo con comillas.

En Linux (CI) pasaban.

Diagnóstico, con una ruta `/c/...` a un repo con `CODEOWNERS`:
- **(a)** `MSYS_NO_PATHCONV=1 git -C /c/... cat-file -e origin/main:.github/CODEOWNERS` da `fatal: cannot change to '/c/...'`, con rc=128.
- **(b)** Sin la variable da `fatal: Not a valid object name origin\main;.github\CODEOWNERS`, con rc=128.
- **(c)** `(cd /c/... && MSYS_NO_PATHCONV=1 git cat-file -e origin/main:.github/CODEOWNERS)` da rc=0.

## Commits

1. `5a77fd6` A1b: la regla de staging entra con `cd` y corre `git cat-file` sin `-C`; criterios.
2. `90866a1` test(A1b): staging con un espacio en la ruta y sin `CDPATH`.
3. `5bd913d` A1b: correcciones de la ronda: `CDPATH='' cd --`, el mismo patrón para el remoto en C4, el veredicto y la lección pendiente.

## Tests

- **Suite completa en Windows sobre `5bd913d`:** `904 ok, 0 fallos`, en 1941 s. Los 3 casos que fallaban en `staging` pasan.
- **CI del push en `5bd913d`** (https://github.com/leon2995/pipeline-prueba/actions/runs/36655609925): el job `hooks` da `904 ok, 0 fallos` con gawk y con mawk, y `node` da 44 y 118 ok.
- **Prueba rápida en Windows (`smoke-a1b.sh`):**
  - **Pasan:** el permitido con rutas `C:/...`, `/c/...` y `/c/...` entre comillas.
  - **Se bloquean:** el que va sin `CODEOWNERS`, el de un directorio inexistente y `HEAD:staging`.

  Con el hook de `staging` fallan justo los dos permitidos con `/c/...`.

## Cómo evitar que se repita

El CI corre solo en Linux y no reproduce la conversión de rutas de MSYS. Antes de mergear un cambio en `guard-commands.sh`, la suite también se corre en Git Bash. La lección nueva queda en `.pipeline/lecciones-pendientes.md`.
