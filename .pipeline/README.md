# Estado operativo del pipeline

Este directorio se commitea. Contiene:

- `modo`: `automatico` o `paso-a-paso`.
- `plan.json`: desglose de subtareas vigente.
- `criterios-<id>.md`: criterios de aceptación de cada subtarea.
- `evidencia/<id>.md`: salida del engineer por subtarea.
- `veredicto-<id>.json` y `veredicto-codex-<id>.json`: veredictos de los auditores.
- `diff-<id>.patch`: diff enviado al segundo auditor.
- `variables-requeridas.txt`: nombres de variables de entorno que el proyecto necesita (nunca valores).
- `urls.json`: URLs base por ambiente para validar deploys.
- `BLOCKED`: existe solo mientras el engineer está bloqueado. Bórralo al resolver.
