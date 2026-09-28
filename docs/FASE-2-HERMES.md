# Fase 2: operación desatendida con Hermes Agent

No arrancar antes de cumplir el criterio de salida de la Fase 1: 15 o 20 tareas reales completadas, tasa de primer intento y acuerdo entre auditores medidos, costo y tiempo por tarea conocidos.

## Qué agrega Hermes

- **Gateway**: das órdenes por WhatsApp o Telegram y recibes reportes ahí mismo. Hoy eso pasa en Claude Code desde la app móvil; con Hermes pasa sin abrir Claude Code.
- **Cron**: tareas que corren solas y te reportan (ver lista abajo).
- **Memoria entre sesiones**: Hermes recuerda qué proyectos hay, en qué quedó cada uno y tus preferencias de reporte.

Hermes no toca el protocolo. El CTO sigue siendo Claude Code con `CLAUDE.md`; los auditores siguen siendo `auditor` y Codex; JEV sigue siendo `scripts/jev.py`. Hermes solo dispara y entrega.

## Qué ya está listo en la Fase 1

- `scripts/run-task.sh "<tarea>" [modo]`: corre una tarea completa con `claude -p` y devuelve el reporte y un `SESSION=<id>`.
- `scripts/resume-task.sh <id> "<respuesta>"`: reanuda la sesión con tu respuesta cuando el reporte terminó en `ESPERANDO OK: ...`.
- `.pipeline/`: todo el estado en archivos legibles (plan, criterios, evidencia, veredictos, reportes). Cualquier orquestador externo puede leerlo sin API.
- `CLAUDE.md` ya sabe comportarse en modo no interactivo (sección "Modo no interactivo").

## Qué falta construir

1. **Servidor.** Un servicio en Railway o un VPS pequeño con: Node, `claude` (con `claude login` de tu Max), `gh auth login`, `railway login`, `codex login`, y el repo clonado. Los logins son de una sola vez por máquina.
2. **Hermes Agent** en ese servidor, con el gateway de WhatsApp o Telegram configurado.
3. **Cerebro de Hermes.** Requiere un proveedor por API key (Anthropic con Haiku, u OpenRouter). Hermes coordina, no programa: el gasto es de coordinación, no de código. Ponle límite de gasto a la key.
4. **Skill `pipeline`** en Hermes, con tres comportamientos:
   - Mensaje "tarea: ..." → ejecuta `run-task.sh`, guarda el `SESSION`, te manda el reporte.
   - Si el reporte contiene `ESPERANDO OK:` → te reenvía la pregunta y espera tu respuesta.
   - Tu respuesta → ejecuta `resume-task.sh <SESSION> "<respuesta>"` y te manda el nuevo reporte.
5. **Cron sugeridos** (cada uno es una llamada a `run-task.sh` con una tarea fija):
   - Diario, madrugada: actualizar dependencias menores y abrir PR a staging.
   - Semanal: resumen de intentos, costo, tiempo y hallazgos por proyecto.
   - Semanal: elegir al azar el 10% de los PR con `pass` y mandártelos para revisión manual.
   - Mensual: leer `LESSONS.md` y proponer cambios al `CLAUDE.md` como PR (tú apruebas).

## Extensiones posibles, ninguna necesaria

- Un tercer auditor de otro proveedor para riesgo alto. Se agrega como comando en `.claude/commands/` (mismo molde que `audit-codex`) y un flag más en `jev.py` con regla de mayoría; el docstring de `jev.py` explica cómo.
- Un agente de investigación en la Fase 1 de propuesta (comparar stacks, precios y estado de librerías con datos actuales).

## Criterio para dar Fase 2 por lista

Una tarea completa disparada desde el teléfono, con una compuerta `ESPERANDO OK` respondida desde el teléfono, sin abrir Claude Code ni la terminal.
