# Criterios: hook-force-push

Riesgo: medio. Toca el control de seguridad del pipeline (`.claude/hooks/guard-commands.sh`); un error deja pasar comandos destructivos o bloquea trabajo legítimo. Sin datos ni integraciones.

- **C1.** `guard-commands.sh` bloquea (exit 2) cualquier push forzado, sin importar la posición del flag: `--force`, `--force-with-lease`, `-f` solo o combinado con otros flags cortos (como `-uf`) y refspecs con `+` (`git push origin +rama`).
- **C2.** `git branch -d` sigue bloqueado a propósito (además de `-D`): borrar ramas siempre requiere OK de Leonardo. El hook tiene un comentario que lo dice.
- **C3.** El hook duplicado del engineer (`guard-commands.sh` en el frontmatter de `.claude/agents/engineer.md`) se conserva sin cambios: es redundancia intencional.
- **C4.** `scripts/test-hooks.sh` alimenta cada hook con JSON de prueba y verifica el código de salida. Mínimo:
  - bloqueados (exit 2): los 4 casos de push forzado de C1, `git branch -D`, `git branch -d`, `git push origin main`, `gh pr merge` con `--admin`;
  - permitidos (exit 0): `git status`, `npm test`, `git push -u origin feat/x`, `git push --follow-tags origin feat/x`.
  El script termina con código distinto de 0 si algún caso falla.
- **C5.** Rama `fix/hook-force-push`, PR contra `staging` con la salida de `scripts/test-hooks.sh` en la descripción. No se mergea sin OK de Leonardo.

## Plan

**Quién implementa:** el CTO (sesión principal), sin delegar al engineer. CLAUDE.md prohíbe que el engineer modifique `.claude/` y `protect-acceptance-tests.sh` lo bloquea; `test-writer` solo escribe en `tests/acceptance/`. Leonardo revisa el diff completo antes de cualquier merge.

1. Rama `fix/hook-force-push` desde `staging`.
2. `guard-commands.sh`: reemplazar el patrón regex de push forzado por una función `is_force_push` (awk) que parte el comando en segmentos (`;`, `&`, `|`, saltos de línea; une continuaciones con `\`), identifica `git ... push` saltando opciones globales de git (y el argumento de `-C`, `-c`, `--git-dir`, etc.) y marca como forzado: tokens que empiezan con `--force`, flags cortos que contienen `f` (`-f`, `-uf`, `-fu`), `--mirror` y sus abreviaturas (fuerza updates), refspecs que empiezan con `+`, y `-c remote.*.push=+...`.
   - **Fail-closed acotado:** si awk falla, bloquea solo los comandos que mencionan `push`, con un mensaje distinto que nombra a awk. El resto de comandos sigue funcionando para poder diagnosticar.
   - **Decisión: el tokenizador no respeta comillas, a propósito.** Así ve dentro de `bash -c "git push -f"`, `sh -c '...'` o `git submodule foreach 'git push -f'`. Costo aceptado: un `git commit -m` cuyo mensaje diga literalmente `git push --force` se bloquea (se usa `git commit -F archivo`). Un mensaje que diga "push --force" sin "git" delante sí pasa. Ambos casos quedan en los tests.
3. Reemplazar `'git branch -D'` por un patrón explícito que cubre `-D`, `-d`, combinados (`-rd`) y `--delete`, con comentario de que es intencional. El patrón exige espacio antes del guion, así que nombres como `fix-db-deploy` no disparan; queda un caso permitido en los tests.
4. Nuevo `scripts/test-hooks.sh` en bash puro: casos de C4, falsos positivos aceptados, awk roto simulado (bloquea `git push -u`, permite `git status`) y casos básicos de los otros hooks (`readonly-guard`, `protect-acceptance-tests`, `only-acceptance-tests`, `run-tests`).
5. Por pedido explícito de Leonardo (agregado después de la auditoría del plan): fijar el modelo del segundo auditor en `.claude/commands/audit-codex.md` con exactamente `-m gpt-5.6-terra -c model_reasoning_effort='"ultra"'` en el `codex exec`, y anotarlo en la fila "Segundo auditor" de la tabla de roles de `CLAUDE.md`.
6. Correr el script, verificar que contra el hook de `staging` falla (prueba de que los tests detectan la regresión), guardar evidencia, auditor Claude y Codex, JEV, PR contra `staging`. Sin merge.

**`.claude/agents/engineer.md` no se toca (C3):** el `guard-commands.sh` duplicado en su frontmatter se conserva sin cambios.

**`settings.json` no se toca.** Sus globs `Bash(git push --force*)` y `Bash(git push -f*)` son una primera capa gruesa con el mismo hueco que el regex viejo; `guard-commands.sh` es la fuente de verdad para push forzado y corre en la sesión principal y en todos los subagentes. Cambiar `settings.json` no está en los criterios de Leonardo.

Fuera de alcance (se reporta, no se implementa): borrado de ramas remotas vía `git push --delete`/`:rama`, aliases de git, config persistente (`git config remote.*.push +...`), sustitución de variables o comandos que oculten el flag en tiempo de ejecución (`V=--force; git push origin feat/x $V`), hooks de archivos con rutas Windows (`\`).
