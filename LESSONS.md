# Lecciones aprendidas

Una línea por patrón de error detectado por el auditor. Se inyecta al engineer en cada delegación. Formato: `- [AAAA-MM-DD] [T#] patrón: qué evitar y qué hacer en su lugar.`

- [2026-09-27] [hook-force-push] filtros de comandos shell: no pelar comillas solo al inicio/fin del token (bash convierte `--for"ce"` en `--force`) ni tomar el exit code del analizador como resultado; quitar comillas y escapes en cualquier posición, saltar redirecciones y exigir una salida explícita del analizador.

