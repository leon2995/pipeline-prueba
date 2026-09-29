# Lecciones pendientes

Aquí van los `new_lesson` de los auditores (Claude y Codex), textuales y con su fuente. No es ruta de gobierno: el CTO la actualiza en la rama de cada subtarea. El engineer nunca recibe este archivo; solo recibe `LESSONS.md`.

`LESSONS.md` cambia solo con un PR de lecciones: uno al cierre de cada proyecto, o cuando haya 5 lecciones pendientes, lo que pase primero.
- Lo abre `talos-bot-leon`, con las pendientes redactadas en el formato de `LESSONS.md` y agrupadas cuando repiten un patrón.
- Leonardo las edita, las descarta o las acepta, y lo mergea.
- En el mismo PR salen de aquí las que se mergearon o descartaron.

Formato: `- [fecha] [subtarea] patrón: qué evitar y qué hacer. (PR #n, archivo del veredicto)`. El texto del patrón es el del auditor. Si el original no trae el prefijo `[fecha] [subtarea]`, lo agrega el CTO.

Criterio de Leonardo para el PR de lecciones: a `LESSONS.md` van como máximo 5 lecciones generales por PR, y se descartan las específicas del hook, que ya viven en el encabezado de `guard-commands.sh`.

## Pendientes

Ninguna.

## Historial

- 2026-09-28, primer PR de lecciones: de 16 pendientes (PRs #4, #6, #10, #11 y #13), 8 se condensaron en 5 lecciones de `LESSONS.md` y se descartaron 8 específicas del hook. El detalle, con el texto original de cada una, está en el cuerpo del PR y en los `veredicto-*.json` citados.
