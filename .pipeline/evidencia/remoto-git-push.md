# Evidencia: remoto-git-push (PR corto de gobierno, paso f)

- **Estado:** auditado. Proceso ligero, excepción aprobada por Leonardo: una ronda del auditor Claude, sin Codex ni JEV. Veredicto `pass`, en `.pipeline/veredicto-remoto-git-push.json`, con 1 media y 4 bajas:
  - Media (pruebas): a la máquina de estados le faltaban casos positivos con opciones globales. Se agregaron 7 casos después de la ronda: `git -C . push`, `git -C "a b" push`, `git -c core.x=y push`, subshells y el mismo con remoto SSH.
  - Baja (falso positivo nuevo): `(cd dir && git push)` bloqueaba por el `)` pegado a `push`. Se corrigió después de la ronda: se quitan el `(` inicial y el `)` final de cada token.
  - Baja (evasión, fuera del modelo de amenaza): una `"` dentro de un valor entre comillas simples esconde el push. Documentada en el encabezado.
  - Baja (fuera del alcance estricto): los prefijos de opciones largas (`--push-opt`, `--rep=`). Documentados en el encabezado.
  - Baja (evidencia): faltaba el conteo del rojo. Ya está abajo.
  - Los cambios posteriores a la ronda son pruebas, dos líneas de lógica y comentarios. No se volvieron a auditar, porque el proceso ligero es de una ronda. Los revisa Leonardo como code owner.
- **Rama:** `fix/remoto-git-push`, rebasada sobre `staging` (7caf338, con el #9). Los tres commits los reescribió `talos-bot-leon` antes del primer push (autor y committer), porque lo abre esa cuenta.
- **Implementó:** el CTO, pruebas e implementación, por la regla de rutas de gobierno.
- **Riesgo:** medio.

## Commits

1. `43aeacd` test(remoto-git-push). Agrega 27 casos a la sección de identidad (C4), con la identidad completa. Reemplaza el caso `git push --repo=origin feat/x`, que ahora bloquea con "no es HTTPS" en lugar de "--repo". Contra el hook anterior: `404 ok, 18 fallos`, exit 1, todos en casos nuevos (los 7 casos agregados después de la ronda son de cobertura y también pasaban con el hook anterior).
2. `4f2845c` fix(remoto-git-push). Cambios en `guard-commands.sh`:
   - normaliza las redirecciones antes de partir;
   - detecta el push en el segmento sin el texto entre comillas;
   - lee los argumentos con `xargs`, con una máquina de tres estados (git, opciones globales, argumentos de push);
   - salta los valores de las opciones y lee `--repo` como git;
   - saca del encabezado los dos límites que se cierran.

   Suite: `422 ok, 0 fallos`; con los 7 casos y la corrección posteriores a la ronda, `429 ok, 0 fallos`.

## Criterios

- **C1.** Pasan `git push 2>&1 | tail -3`, `git push >/dev/null`, `git push origin feat/x 2>/dev/null` y `git push 2> err.txt`, además de `git push` sin remoto. Con el hook anterior bloqueaban con remoto `2>` o `>/dev/null`.
- **C2.** Casos del texto entre comillas:
  - pasan `git commit -m "docs: el hook revisa git push antes del PR"`, `gh pr create --title "T4: git push con helper" --body-file b.md`, `git commit -m 'git push origin feat/x'` y `git push origin feat/x -o "ci skip"`;
  - bloquean con "no es HTTPS" `git push "git@github.com:o/r.git" feat/x`, `git push "https://leon2995@github.com/o/r.git" feat/x` y `git commit -m x && git push git@github.com:o/r.git feat/x`;
  - `git push origin "feat/x` (comillas sin cerrar) bloquea con "no pude leer".
- **C3.** Pasan `-o ci.skip`, `--push-option=ci.skip` y `--push-option ci.skip`. Bloquean con "no es HTTPS", porque el remoto real es SSH:
  - `-o`, `--push-option`, `--receive-pack` y `--exec` con un valor `https://github.com/o/r.git` delante del remoto SSH;
  - `-uo`, con el mismo valor;
  - `-oci.skip`, con el valor pegado;
  - `--receive-pack=x --exec=y`.
- **C4.** Pasan `git push --repo=origin` y `git push --repo origin`. Bloquean con "no es HTTPS" `--repo git@github.com:o/r.git`, `--repo=https://leon2995@github.com/o/r.git` y `--repo=origin feat/x`.
- **C5.** Siguen pasando los casos existentes de C4 y de toda la suite (`429 ok, 0 fallos`). `analizar_git`, el bloque de `gh pr merge` y la sección de credenciales no cambian.
- **C6.** El encabezado conserva los límites de impresión del entorno, remoto por defecto `origin` sin `pushRemote`, email, cobertura de C4 y separadores dentro de comillas. Saca las opciones con valor leídas como remoto y el falso positivo. Después de la ronda suma los límites de las comillas anidadas y de los prefijos de opciones largas. En `SETUP.md`, el punto 4 del paso g pasa de describir el falso positivo a verificar que un push normal pase.

## Tests

- **Comando:** `bash scripts/test-hooks.sh`.
- **Resultado:** `429 ok, 0 fallos` (Git Bash, gawk). La salida completa está en `.pipeline/test-hooks-salida.txt`.
- **Rojo y mutación:** `404 ok, 18 fallos`: 3 de redirecciones, 2 de texto entre comillas (`-m` y `--title`), 1 de comillas sin cerrar, 2 de `-o` con valor que antes se leía como remoto, 5 de opciones con valor delante de un remoto SSH que antes pasaban, 2 de `--repo` que antes bloqueaba y 3 de `--repo` con el motivo nuevo. El hook anterior es el de `fix/nombre-agente`, que va a ser el de `staging`.
- **CI:** se corre al hacer push, como `talos-bot-leon`.
