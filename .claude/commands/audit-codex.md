---
description: Segundo auditor con Codex (ChatGPT Business). Uso /audit-codex T1
allowed-tools: Bash(git diff*), Bash(codex exec*), Bash(cat *), Read, Write
---

Corre el segundo auditor, Codex, para la subtarea $ARGUMENTS. Codex no ve nada de la conversación: solo criterios y diff.

1. Genera el diff de la rama actual contra `staging`:
   `git diff staging...HEAD > .pipeline/diff-$ARGUMENTS.patch`
2. Escribe el prompt completo en un archivo (está en `.gitignore`) y pásaselo a Codex por entrada estándar con `-`, en sandbox de solo lectura. Así no depende del límite de 32.767 caracteres de la línea de comandos de Windows.

```bash
cat > .pipeline/prompt-codex-$ARGUMENTS.txt <<EOF
$(cat .claude/prompts/auditor-codex.md)

TASK: $ARGUMENTS

CRITERIOS:
$(cat .pipeline/criterios-$ARGUMENTS.md)

LESSONS:
$(cat LESSONS.md)

DIFF:
$(cat .pipeline/diff-$ARGUMENTS.patch)
EOF
```

```bash
codex exec -m gpt-5.6-sol -c model_reasoning_effort='"high"' --sandbox read-only --output-last-message .pipeline/veredicto-codex-$ARGUMENTS.json - < .pipeline/prompt-codex-$ARGUMENTS.txt
```

3. Lee `.pipeline/veredicto-codex-$ARGUMENTS.json`. Si no es JSON válido, agrega la instrucción al final del archivo de prompt y vuelve a correr una sola vez el mismo `codex exec` del paso 2:

```bash
cat >> .pipeline/prompt-codex-$ARGUMENTS.txt <<'EOF'

Responde únicamente con el JSON, sin markdown
EOF
```

4. No interpretes el veredicto tú. Pásalo a JEV con `--codex .pipeline/veredicto-codex-$ARGUMENTS.json`. Si difiere del veredicto de Claude, JEV devolverá HUMAN.
