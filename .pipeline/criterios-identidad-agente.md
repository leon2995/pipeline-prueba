# Criterios: identidad-agente (paso g, PR de gobierno)

Riesgo: **medio**. Activa la identidad obligatoria de `talos-bot-leon` (C4 de cuenta-agente): desde que el archivo exista, el hook bloquea commits, push y escrituras en GitHub sin la identidad completa. Es el punto 2 del paso g de `SETUP.md`, definido en el plan de T1 que aprobó Leonardo: lo abre `talos-bot-leon`, queda bloqueado hasta la aprobación de Leonardo como code owner, y él lo aprueba y lo mergea. La lógica ya está probada en `scripts/test-hooks.sh`, sobre copias del hook con el archivo.

- **C1.** `.claude/identidad-agente.txt` contiene una sola línea: `talos-bot-leon`.
- **C2.** Con el archivo presente en la copia de trabajo, el commit, el push y el `gh pr create` de este PR pasan con la identidad de la sesión. `git push` sin remoto y con `2>&1 | tail -3` pasa. Un push a un remoto SSH se bloquea con "no es HTTPS".
- **C3.** `SETUP.md`, paso c: el token vence el 2026-10-28, en hora local (2026-10-29 02:05 UTC), y hay que rotarlo antes del 2026-10-15. Lo pidió Leonardo.

Verificación posterior al PASS: el PR queda bloqueado hasta la aprobación de Leonardo; después del merge, un push normal desde una rama de `staging` pasa con la identidad obligatoria.
