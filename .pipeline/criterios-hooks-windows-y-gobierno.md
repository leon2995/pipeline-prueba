# Criterios: hooks-windows-y-gobierno

Riesgo: medio. Toca controles del pipeline (hooks de archivos del engineer y del test-writer, y el merge a `staging`); un error deja escribir donde no se debe, bloquea trabajo legítimo o deja mergear un PR de gobierno sin Leonardo.

**Modelo de amenaza: errores del agente, no ofuscación deliberada.** Los hooks frenan lo que un agente haría por costumbre o descuido: escribir con la ruta Windows real que entrega Claude Code, mergear a `staging` un PR de gobierno o agregar `--delete-branch` al mergear. Quedan fuera de alcance: `..` en rutas, diferencias de mayúsculas en rutas Windows, mergear con `gh api` o desde la web, y sintaxis de shell rebuscada. El control efectivo sobre `main` y `staging` sigue siendo la protección de ramas de GitHub.

- **C1.** `protect-acceptance-tests.sh` y `only-acceptance-tests.sh` convierten `\` en `/` en la ruta antes de comparar. Con rutas Windows absolutas (`C:\Users\...\tests\acceptance\x.py`) se comportan igual que con `/`: `protect-acceptance-tests.sh` bloquea `tests/acceptance/`, `.claude/`, `CLAUDE.md`, `LESSONS.md`, `docs/adr/` y `.github/workflows/`, y permite `src/` y `tests/unit/`; `only-acceptance-tests.sh` solo permite `tests/acceptance/`.
- **C2.** `scripts/test-hooks.sh` tiene esos mismos casos con rutas Windows absolutas, los que bloquean y los que permiten, para los dos hooks.
- **C3.** `.claude/rutas-gobierno.txt` es la única fuente de las rutas de gobierno: `CLAUDE.md` y `LESSONS.md` en cualquier nivel, `.claude/` en cualquier nivel, `.github/` en la raíz, `scripts/jev.py`, `scripts/test-hooks.sh`, `scripts/run-task.sh`, `scripts/resume-task.sh` y `scripts/watch-deploy.sh`. `guard-commands.sh` lee ese archivo y bloquea `gh pr merge` a `staging` si el PR modifica alguna de esas rutas, consultándolo con `gh pr view <n> --json files`; lo permite cuando ninguna ruta del PR está en la lista. Siguen bloqueados la base distinta de `staging` y `--admin`.
- **C4.** Fail-closed: se bloquea el merge si `gh` falla, si no devuelve archivos, si la lista está incompleta (`changedFiles` mayor que las rutas devueltas; `gh` devuelve como máximo 100) o si `.claude/rutas-gobierno.txt` no existe, no se puede leer o no tiene reglas.
- **C5.** La suite, con un `gh` falso en el PATH, cubre: merge permitido (base `staging`, solo `src/`); un bloqueo por cada ruta de `.claude/rutas-gobierno.txt`, incluidos `CLAUDE.md` y `.claude/` anidados; una ruta parecida que no es de gobierno (`docs/claude-notas.md`) permitida; base `main`; `gh` que falla; lista incompleta; PR sin archivos; y archivo de rutas ausente. La suite queda en verde y contra los hooks de `staging` los casos nuevos fallan.
- **C6.** `CLAUDE.md`, en "Siempre requieren OK explícito de Leonardo", tiene la regla de mergear a `staging` un PR que modifique rutas de gobierno, citando `.claude/rutas-gobierno.txt` sin repetir la lista.
- **C7.** `SETUP.md` dice "ChatGPT Business" y no queda "ChatGPT Pro" en el repo, salvo en el historial de `.pipeline/`.
- **C8.** `guard-commands.sh` bloquea `gh pr merge` con `-d` o `--delete-branch` (también combinado con otros flags cortos, como `-sd`), con el mismo mensaje de borrado de ramas. Hay casos en la suite.

Verificación posterior al PASS (fuera de los criterios del auditor): PR contra `staging` con CI en verde. Este PR lo mergea Leonardo, porque toca rutas de gobierno.

## Plan

**Quién implementa:** el CTO (sesión principal). Todo es `.claude/`, `CLAUDE.md`, `scripts/test-hooks.sh` o `SETUP.md`. Flujo de riesgo medio: auditoría del plan, implementación, auditor Claude, Codex (`/audit-codex`, stdin, `gpt-5.6-sol` esfuerzo `high`) y JEV.

1. **Rutas Windows.** En los dos hooks de archivos, justo después de leer la ruta y antes del `case`: `path=${path%$'\r'}` (jq nativo de Windows entrega CRLF; el bash de Git para Windows ya quita ese `\r` al capturar, pero otros entornos no) y `path=${path//\\//}`. Los patrones no cambian.
2. **`.claude/rutas-gobierno.txt`.** Una regla por línea; `#` inicia comentario; se ignoran líneas vacías. Al leer se quitan `\r` y espacios al inicio y al final (el archivo puede quedar con CRLF). Algoritmo de coincidencia, sobre la ruta y la regla en minúsculas (más conservador):
   - `**/X/` (directorio en cualquier nivel): la ruta empieza por `x/` o contiene `/x/`. Así `**/.claude/` cubre `.claude/settings.json` en la raíz y `sub/.claude/x`, pero no `.claude-old/x`.
   - `**/X` (archivo en cualquier nivel): la ruta es `x` o termina en `/x`. Cubre `CLAUDE.md` y `sub/CLAUDE.md`, pero no `docs/MYCLAUDE.md`.
   - `X/` (directorio en la raíz): la ruta empieza por `x/`. `.github/` no cubre `docs/.github/x`.
   - `X` (archivo en la raíz): igualdad exacta. `scripts/jev.py` no cubre `scripts/jev.py.bak` ni `src/scripts/jev.py`.

   Contenido: `**/CLAUDE.md`, `**/LESSONS.md`, `**/.claude/`, `.github/`, `scripts/jev.py`, `scripts/test-hooks.sh`, `scripts/run-task.sh`, `scripts/resume-task.sh`, `scripts/watch-deploy.sh`. El archivo queda protegido por `**/.claude/`.
3. **`guard-commands.sh`, bloque de `gh pr merge`** (se detecta como hoy, con `(^|[;&| ])gh pr merge`):
   - **Un merge por comando:** si `gh pr merge` aparece más de una vez en el comando, bloquea con "un merge por comando". Evita que `gh pr merge 6 && gh pr merge 5` valide solo el último.
   - **Flags**, mirando solo los tokens que siguen a `gh pr merge` hasta el primer `;`, `&`, `|` o salto de línea: `--admin` bloquea (como hoy). Para C8 bloquea un token que cumpla `^-[A-Za-z]+$` y contenga `d` (`-d`, `-sd`, `-ds`), o que empiece por `--delete-branch`, con el mismo mensaje de borrado de ramas que usa el analizador (una sola variable). No bloquea `--merge`, `--rebase`, `--squash`, `--auto`, `--disable-auto`, `--body`, `--body-file`, `--subject`, `--match-head-commit`, `-s`, `-m` ni `-r`.
   - **Reglas:** lee `.claude/rutas-gobierno.txt` (ruta relativa al hook). Si falta, no se puede leer o no tiene reglas después de quitar comentarios y líneas vacías, bloquea.
   - **Consulta 1**, la que pidió Leonardo: `gh pr view <n> --json number,baseRefName,changedFiles,files --jq '.number, .baseRefName, .changedFiles, (.files|length), .files[].path'`, con el jq que trae `gh`. Si el PR no se puede identificar, `gh` falla y se bloquea.
   - **Consulta 2**, para renombres: `files` solo trae la ruta nueva de un archivo movido. Se suma `gh api repos/{owner}/{repo}/pulls/<number>/files --paginate --jq '.[] | select(.previous_filename) | .previous_filename'`; los nombres anteriores también se comparan contra las reglas. Si esta consulta falla, bloquea. Cubre `git mv scripts/jev.py scripts/router/jev.py` y renombres de un archivo de gobierno a otra carpeta.
   - Bloquea si: una consulta falla o la primera sale vacía; la base no es `staging`; `changedFiles` no es un número, es 0 o no coincide con las rutas devueltas (lista incompleta: `gh` devuelve como máximo 100); o alguna ruta nueva o anterior coincide con una regla. El mensaje nombra la ruta y dice que el PR lo mergea Leonardo, citando `.claude/rutas-gobierno.txt`.
4. **Suite.** `test-hooks.sh` suma:
   - **Rutas Windows:** los mismos casos de archivo de los dos hooks con rutas Windows absolutas, más `C:\...\CLAUDE.md` con `\r` final inyectado en el JSON.
   - **`gh` falso** (script en el PATH, mismo mecanismo que el awk roto) que responde por número de PR a `gh pr view <n> --json number,baseRefName,changedFiles,files`, a `gh api repos/{owner}/{repo}/pulls/<n>/files` y, para que la mutación contra `staging` sea válida, también a la consulta vieja `--json baseRefName -q .baseRefName`. Cualquier otra forma de llamarlo falla.
   - **Merges:** permitido (`staging`, solo `src/`); un bloqueo por cada una de las 9 reglas; `CLAUDE.md` y `.claude/` anidados; rename desde `scripts/jev.py`; rutas parecidas permitidas (`docs/claude-notas.md`, `docs/MYCLAUDE.md`, `scripts/jev.py.bak`, `src/scripts/jev.py`, `.claude-old/x`, `docs/.github/x`); base `main`; consulta 1 que falla; consulta 2 que falla; lista incompleta; PR sin archivos; dos merges encadenados (uno de gobierno).
   - **Flags:** `-d`, `--delete-branch`, `-sd` bloquean; `--merge`, `--rebase`, `--auto`, `--disable-auto`, `-s`, `-m`, `-r`, `--subject x`, `--body x` permiten (con número de PR antes de los flags).
   - **Archivo de reglas:** copia de `guard-commands.sh` y `_lib.sh` en `$tmp/x/.claude/hooks/` con el `gh` falso respondiendo `staging` y solo `src/`: (1) control con `rutas-gobierno.txt` copiado, permite; (2) sin el archivo, bloquea; (3) con un archivo de solo comentarios y líneas vacías, bloquea; (4) ilegible con `chmod 000`, bloquea; si `chmod` no quita la lectura (Windows), el caso se marca omitido y se declara sin cubrir; (5) reglas con CRLF, siguen bloqueando `CLAUDE.md`.
   - **Mutación:** la suite contra los hooks de `staging` debe fallar en los casos nuevos; la salida se guarda en la evidencia.
5. **Evidencia con `gh` real:** el hook bloquea `gh pr merge 1` y `gh pr merge 2` (ya mergeados, tocaron `.claude/`). Solo consulta; no mergea nada. No hay hoy un PR real sin rutas de gobierno con base `staging`: el caso permitido queda cubierto por el `gh` falso.
6. **`CLAUDE.md`:** una línea en "Siempre requieren OK explícito de Leonardo" que cita `.claude/rutas-gobierno.txt` sin repetir la lista.
7. **`SETUP.md`:** "ChatGPT Pro" → "ChatGPT Business".
8. Suite completa en verde, mutación contra `staging`, evidencia, auditor Claude, Codex, JEV y PR contra `staging` sin mergear.

### Ajustes tras la auditoría del plan (vuelta 2: pass, 1 media y 5 bajas, todas incorporadas)

9. `--auto` se bloquea: GitHub mergearía después, con un estado del PR que el hook no revisó. `--disable-auto` sigue permitido. En la suite, `--auto` pasa a los bloqueados.
10. Número de PR: los argumentos que siguen a `gh pr merge` se separan respetando comillas (`xargs`, que no ejecuta nada; comillas sin cerrar → bloquea). Se saltan los valores de `-A`, `-b`, `-F`, `-t`, `--author-email`, `--body`, `--body-file`, `--match-head-commit` y `--subject`. `-R`/`--repo` bloquea (otro repositorio). Más de un argumento posicional → bloquea. Sin número se consulta el PR de la rama actual. `"$target"` va entre comillas.
11. Una regla con `*` fuera del prefijo `**/` bloquea con "regla no soportada".
12. Archivo ilegible: se trata como ilegible cualquier cosa que no sea un archivo regular legible o cuya lectura falle; en la suite se simula con un directorio llamado `rutas-gobierno.txt` (funciona también en Windows), además de ausente, vacío y CRLF, y un control que permite.
13. Los casos nuevos de merge y flags comprueban también que stderr nombre el motivo (la ruta de gobierno, "borrar ramas", "un merge por comando", "lista incompleta", etc.), no solo el código de salida.
14. Evidencia con `gh` real: stderr completo de `gh pr merge 1` y `gh pr merge 2`, que debe nombrar una ruta concreta del PR (prueba que las dos consultas reales funcionaron); y un permitido real sin mergear: copia del hook con un `rutas-gobierno.txt` de una sola regla que no aplica (`nada/`) y `gh pr merge 1` por stdin, que debe salir con 0.

### Intento 2 (JEV devolvió FIX en el intento 1: Claude fail con 1 alta, 1 media y 1 baja; Codex fail con 3 altas y 1 media)

15. Número de PR explícito: sin número, `gh pr view` resolvería el PR de la rama actual en el momento del hook, que puede no ser el que se mergea (`git switch fix/gobierno && gh pr merge --squash`). Si el objetivo no es un número, se bloquea con "indica el número del PR". La Fase 4 de `CLAUDE.md` pasa a `gh pr merge <n> --squash`.
16. Redirecciones: antes de leer los argumentos se normalizan `2>&1`, `>&2`, `&>` y `>|`, y en el bucle se descartan los tokens de redirección con su destino (`2>/dev/null`, `> log.txt`, `>log.txt`).
17. Separadores entre comillas: el texto de `gh pr merge` se corta en el primer `;`, `&`, `|` o salto de línea fuera de comillas y sin escapar (`--body "R&D; listo"` ya no se corta).
18. Formas con `=`: `--admin=*` bloquea igual que `--admin`. En los grupos cortos se quita el `=valor` antes de mirar las letras: `-d=true` y `-sd=true` bloquean.
19. Grupos cortos con valor: `d` y `R` se buscan solo en las letras anteriores al primer flag que lleva valor (`A`, `b`, `F`, `t`, `R`); lo que sigue a ese flag es su valor (`-tdocs` es el asunto "docs", no un borrado). `R` como flag con valor bloquea (otro repositorio).
20. C2: `only-acceptance-tests.sh` recibe los mismos casos de rutas Windows que `protect-acceptance-tests.sh` (`.claude/`, `CLAUDE.md`, `LESSONS.md`, `docs/adr/`, `.github/workflows/` bloquean).
21. Límite conocido que se deja documentado en el hook: el texto `gh pr merge` dentro de un `--body` cuenta como segundo merge y bloquea con "un merge por comando" (conservador).

### Cierre (decisión de Leonardo tras HUMAN en el intento 2)

Sin intento 3. Los hallazgos del intento 2 quedan como límites conocidos, documentados en el hook y en el PR: `cd` a otro repositorio antes del merge; merges desde PowerShell u otra herramienta distinta de Bash; `GH_REPO` dentro de `--body`; continuación de línea; `gh.exe` y `bash -c`. El hook sigue siendo contra errores; el control real sobre los PRs de gobierno irá en el servidor (cuenta de GitHub propia del agente y CODEOWNERS) en el siguiente PR. Las lecciones nuevas irán en PRs aparte (cambio de protocolo en el siguiente PR).

**Consecuencia declarada (resuelta por Leonardo: las lecciones van en PRs aparte, desde el siguiente PR):** `**/LESSONS.md` es ruta de gobierno y la Fase 3 paso 5 agrega `new_lesson` a `LESSONS.md` dentro de la subtarea. Todo PR de subtarea con lección nueva lo mergeará Leonardo. La alternativa es juntar las lecciones en PRs aparte; eso cambia el protocolo y no está en este PR.

Fuera de alcance (modelo de amenaza): `..` en rutas, mayúsculas en rutas Windows, `gh api` o la web para mergear, flags con valor que confunden la detección del número de PR (terminan en `gh` fallando y bloqueando).
