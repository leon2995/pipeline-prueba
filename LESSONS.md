# Lecciones aprendidas

Una línea por patrón de error detectado por el auditor. Se inyecta al engineer en cada delegación. Formato: `- [AAAA-MM-DD] [T#] patrón: qué evitar y qué hacer en su lugar.`

- [2026-09-27] [hook-force-push] filtros de comandos shell: no pelar comillas solo al inicio/fin del token (bash convierte `--for"ce"` en `--force`) ni tomar el exit code del analizador como resultado; quitar comillas y escapes en cualquier posición, saltar redirecciones y exigir una salida explícita del analizador.
- [2026-09-27] [hook-force-push] criterios: Los criterios de aceptación solo deben pedir lo que se puede verificar antes del PASS. Lo que ocurre después (abrir el PR, deploy, comentarios en el PR) va como verificación post-PASS y no como criterio del auditor.
- [2026-09-27] [hook-force-push] filtros de comandos shell: partir por `;`, `&`, `|` sobre el texto crudo deja una evasión (un separador dentro de `"a&b"` o de una URL con `&` corta el análisis y deja huérfano el flag real). Si el modelo de amenaza incluye ofuscación, partir solo por separadores fuera de comillas y sin escapar; si es solo errores, documentarla como evasión conocida.
- [2026-09-28] [hook-force-push] criterios de seguridad: Los criterios de controles de seguridad deben declarar su modelo de amenaza: errores o ofuscación deliberada. Sin eso, los auditores encuentran evasiones sin fin.

