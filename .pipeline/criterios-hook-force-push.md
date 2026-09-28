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
  *Verificación (anotada con OK de Leonardo):* C5 se verifica con el PR abierto, después de que JEV devuelva PASS; por protocolo no puede tener evidencia dentro del diff auditado. El criterio no cambia.

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

### Intento 2 (JEV devolvió FIX en el intento 1)

Los dos auditores encontraron evasiones reales porque el hook no normalizaba lo que bash sí normaliza. Cambios:

7. Un solo analizador awk (`analizar_git`) para push forzado, push a `main` y borrado de ramas; imprime una palabra (`force`, `main`, `borrado`, `limpio`) y el hook decide por esa salida, no por el código de salida de awk. Cualquier otra salida (awk ausente, caído o que sale con 0, 1 o 2 sin imprimir) bloquea los comandos que mencionan `push` o `branch`.
8. Normalización antes de comparar: quita redirecciones (`2>&1`, `&>`, `>|`, `> archivo`, `>archivo`) antes de partir por `&`; en cada palabra quita comillas, `\`, `$`, `(`, `)`, `{`, `}` en cualquier posición (`--for"ce"`, `-"f"`, `p\ush`, `$'-f'`, `'-d'`). Reconoce `git` también como ruta Windows (`...\git.exe`).
9. Abreviaturas: bloquea cualquier prefijo de `--force-with-lease`, `--force-if-includes` y `--mirror` desde tres caracteres (`--f`, `--m`); los prefijos ambiguos igual fallan en git, así que bloquearlos no cuesta nada. `--fol` (follow-tags) y `--dry-run` pasan.
10. Push a `main` pasa al analizador (antes era grep y se evadía con `'main'`): `main`, `HEAD:main`, `HEAD:refs/heads/main`. Deja de bloquear por error `git push origin x && git checkout main`.
11. Borrado de ramas, por el motivo de C2 ("borrar ramas siempre requiere mi OK"): además de `git branch`, cubre ramas remotas (`git push --delete`, `-d`, `:rama`) y `git update-ref -d`.
12. Config de git por variables de entorno (`GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_KEY_n`/`VALUE_n`) con `push=+` o `mirror`, igual que `-c`.
13. Tests nuevos para cada evasión reportada, `\r` final (CRLF de jq en Windows) y awk roto con salida 0, 1 y 2.

**`.claude/agents/engineer.md` no se toca (C3):** el `guard-commands.sh` duplicado en su frontmatter se conserva sin cambios.

**`settings.json` no se toca.** Sus globs `Bash(git push --force*)` y `Bash(git push -f*)` son una primera capa gruesa con el mismo hueco que el regex viejo; `guard-commands.sh` es la fuente de verdad para push forzado y corre en la sesión principal y en todos los subagentes. Cambiar `settings.json` no está en los criterios de Leonardo.

Fuera de alcance (se reporta, no se implementa): aliases de git, config persistente (`git config remote.*.push +...`), sustitución de variables o comandos que oculten el flag en tiempo de ejecución (`V=--force; git push origin feat/x $V`), hooks de archivos con rutas Windows (`\`).
