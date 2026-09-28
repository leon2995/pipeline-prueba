# Lecciones aprendidas

Una línea por patrón de error detectado por el auditor. Se inyecta al engineer en cada delegación. Formato: `- [AAAA-MM-DD] [T#] patrón: qué evitar y qué hacer en su lugar.`

- [2026-09-27] [hook-force-push] criterios: Los criterios de aceptación solo deben pedir lo que se puede verificar antes del PASS. Lo que ocurre después (abrir el PR, deploy, comentarios en el PR) va como verificación post-PASS y no como criterio del auditor.
- [2026-09-28] [hook-force-push] criterios de seguridad: Los criterios de controles de seguridad deben declarar su modelo de amenaza: errores o ofuscación deliberada. Sin eso, los auditores encuentran evasiones sin fin.

