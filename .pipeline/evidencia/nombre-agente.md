# Evidencia: nombre-agente

- **Estado:** listo para auditoría de código.
- **Rama:** `fix/nombre-agente`, desde `staging` en `f55f12c`.
- **Implementó:** el CTO (sesión principal), pruebas e implementación, por la regla de rutas de gobierno.
- **Riesgo:** bajo. Se renombra la cuenta en textos, la plantilla y las pruebas; la lógica del hook no cambia.
- **Motivo:** `talos-bot` estaba ocupado. Leonardo creó `talos-bot-leon`, con 2FA y el email privado activo; su email noreply es `335185800+talos-bot-leon@users.noreply.github.com`.

## Commits

1. `ccddcde` test(nombre-agente). La suite espera `talos-bot-leon` en los mensajes de C4 y en la plantilla, con el email completo (antes solo comprobaba el sufijo). Contra los archivos de `staging` da `361 ok, 34 fallos`, exit 1, con dos grupos de fallos:
   - 30 en la sección de identidad (C4): el mensaje del hook sigue diciendo `talos-bot`;
   - 4 en la plantilla: el nombre y el email de autor y committer.

   Es también la mutación: los archivos de `staging` son los del commit anterior, salvo la suite y los criterios.
2. `ea38720` fix(nombre-agente). Cambia `talos-bot` por `talos-bot-leon` en:
   - `CLAUDE.md`;
   - `SETUP.md`, con dos notas: en el paso a, que `talos-bot` estaba ocupado y cuál es el email noreply; en el paso f, que el email ya viene en la plantilla;
   - `.claude/settings.local.example.json`, con el email completo;
   - los comentarios y mensajes de `guard-commands.sh`.

## Criterios

- **C1.** `grep` de `talos-bot` en los cinco archivos: cada aparición es parte de `talos-bot-leon`, sin `talos-bot-leon-leon`. `~/.talos-gh`, `talos_env`, `talos_git` y `talos_base` no cambian.
- **C2.** La plantilla trae `GIT_AUTHOR_NAME` y `GIT_COMMITTER_NAME` = `talos-bot-leon`, y `GIT_AUTHOR_EMAIL` y `GIT_COMMITTER_EMAIL` = `335185800+talos-bot-leon@users.noreply.github.com`. La suite lo comprueba con `campo`, con igualdad exacta.
- **C3.** En `guard-commands.sh` cambian 11 líneas: 8 de comentarios y 3 con textos de mensajes (`env -i`, cambio de cuenta y `falta=...`). Ninguna condición, patrón ni variable cambia. La suite da `395 ok, 0 fallos` en local (Git Bash, gawk). En [CI del push de `ea38720`](https://github.com/leon2995/pipeline-prueba/actions/runs/36476027019) también da `395 ok, 0 fallos`, con GNU Awk 5.2.1 y con mawk 1.3.4.
- **C4.** `SETUP.md`: el paso a nombra la cuenta, dice que `talos-bot` estaba ocupado y da el email noreply; el paso f dice que el email ya viene en la plantilla; el paso g crea `.claude/identidad-agente.txt` con `talos-bot-leon`.
- **C5.** `git diff staging...fix/nombre-agente` no toca ningún archivo histórico de `.pipeline/`. Solo agrega `criterios-nombre-agente.md` y esta evidencia, y actualiza `test-hooks-salida.txt`.

## Tests

- **Comando:** `bash scripts/test-hooks.sh`.
- **Resultado:** `395 ok, 0 fallos`. La salida completa está en `.pipeline/test-hooks-salida.txt`.
- **Rojo y mutación:** `361 ok, 34 fallos`.
