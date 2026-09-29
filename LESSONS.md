# Lecciones aprendidas

Una línea por patrón de error detectado por el auditor. Se inyecta al engineer en cada delegación. Formato: `- [AAAA-MM-DD] [T#] patrón: qué evitar y qué hacer en su lugar.`

- [2026-09-27] [hook-force-push] criterios: Los criterios de aceptación solo deben pedir lo que se puede verificar antes del PASS. Lo que ocurre después (abrir el PR, deploy, comentarios en el PR) va como verificación post-PASS y no como criterio del auditor.
- [2026-09-28] [hook-force-push] criterios de seguridad: Los criterios de controles de seguridad deben declarar su modelo de amenaza: errores o ofuscación deliberada. Sin eso, los auditores encuentran evasiones sin fin.
- [2026-09-28] [vencimiento-token] documentar contra la herramienta real: todo comando, flag, scope, clave de configuración o salida esperada que un documento o un criterio afirma se verifica contra la herramienta o el código antes de escribirlo, y se corre donde existen sus variables. Si un documento dice que un control bloquea algo, se confirma contra el control.
- [2026-09-28] [cuenta-agente] controles fail-closed: verificar la ruta de credenciales que usará la operación protegida; comprobar otra CLI o solo la presencia de variables permite que las pruebas pasen con una configuración inválida o con credenciales de otra cuenta.
- [2026-09-28] [cuenta-agente] dos cuentas en una máquina: los valores por defecto de los flujos interactivos pueden cambiar el estado global (gh auth login ofrece reemplazar la credencial de git de la cuenta principal). Indica la respuesta, verifica después el helper del sistema y escribe cada comando de la cuenta del agente con su prefijo de configuración completo.
- [2026-09-28] [lecciones] excepciones al protocolo: al agregar una excepción a un paso, actualiza todas las compuertas que lo imponen (niveles de riesgo, auditoría del plan, router) y no solo el párrafo nuevo. Si no, quedan dos reglas contradictorias sin precedencia.
- [2026-09-28] [remoto-git-push] pruebas de reglas nuevas: prueba cada rama nueva de un analizador o de una máquina de estados con al menos un caso que deba pasar, además de los que deben fallar.

