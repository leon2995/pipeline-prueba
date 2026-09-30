# Criterios: A1b (regla de staging en Windows)

Riesgo: **medio**. Es una corrección de A1 (#19) en `guard-commands.sh`, que es ruta de gobierno. Va con proceso ligero: una ronda del auditor Claude y la aprobación de Leonardo como code owner. Lo implementa el CTO.

**Origen.** La suite completa en Windows (Git Bash) sobre `staging` en `9ce952e` falló en 3 casos, todos de C7 de A1: `git -C <dir> push origin origin/main:refs/heads/staging` (y `:staging`, y con comillas) se bloquea aunque `origin/main` de `<dir>` tenga `.github/CODEOWNERS`. En Linux (CI) pasa.
- **La causa:** el hook corría `MSYS_NO_PATHCONV=1 git -C <dir> cat-file -e origin/main:.github/CODEOWNERS`.
  - **Con la variable:** Git Bash no convierte una ruta `/c/...` o `/tmp/...` de `-C`, y el `git.exe` nativo no la encuentra.
  - **Sin la variable:** convierte `origin/main:.github/CODEOWNERS` en `origin\main;.github\CODEOWNERS`.
- **El efecto:** falla cerrado, porque bloquea de más. Aun así rompe el paso 8 de `/crear-repo` (A2) si la ruta va con estilo MSYS.

## Criterios

- **C1.** El chequeo de `CODEOWNERS` entra al directorio con `CDPATH='' cd --`, que resuelve bash, y corre `git cat-file` sin `-C`, con `MSYS_NO_PATHCONV=1`. Si el directorio no existe, solo aparece por `CDPATH` o no tiene `CODEOWNERS` en `origin/main`, sigue bloqueando. C4 lee el remoto de `git -C <dir> push` con el mismo patrón.
  - *Ajustado después de la ronda del auditor:* `CDPATH` y `--`, y el mismo patrón en C4.
- **C2.** En Windows, con rutas `/c/...`, `C:/...`, `/tmp/...` y con un espacio en la ruta, el push permitido pasa. El que va sin `CODEOWNERS`, con un directorio inexistente o con `HEAD:staging` se bloquea.
- **C3.** `bash scripts/test-hooks.sh` da 0 fallos en CI (gawk y mawk) y en Windows. Los 3 casos que fallaban en `staging` pasan.
