---
description: Segundo auditor con Codex (ChatGPT Pro). Uso /audit-codex T1
allowed-tools: Bash(git diff*), Bash(codex exec*), Bash(cat *), Read, Write
---

Corre el segundo auditor, Codex, para la subtarea $ARGUMENTS. Codex no ve nada de la conversación: solo criterios y diff.

1. Genera el diff de la rama actual contra `staging`:
   `git diff staging...HEAD > .pipeline/diff-$ARGUMENTS.patch`
2. Ejecuta Codex en sandbox de solo lectura, con el prompt fijo del auditor:

```bash
codex exec --sandbox read-only --output-last-message .pipeline/veredicto-codex-$ARGUMENTS.json \
"$(cat .claude/prompts/auditor-codex.md)

TASK: $ARGUMENTS

CRITERIOS:
$(cat .pipeline/criterios-$ARGUMENTS.md)

LESSONS:
$(cat LESSONS.md)

DIFF:
$(cat .pipeline/diff-$ARGUMENTS.patch)"
```

3. Lee `.pipeline/veredicto-codex-$ARGUMENTS.json`. Si no es JSON válido, vuelve a correr una sola vez agregando al final del prompt: "Responde únicamente con el JSON, sin markdown".
4. No interpretes el veredicto tú. Pásalo a JEV con `--codex .pipeline/veredicto-codex-$ARGUMENTS.json`. Si difiere del veredicto de Claude, JEV devolverá HUMAN.
