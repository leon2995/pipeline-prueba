# Evidencia: T3b (instalador v1)

- **Estado:** listo para la auditoría de código. Riesgo bajo y protocolo normal: auditor Claude y JEV.
- **Rama:** `feat/T3b-instalador`, desde `staging` en `ddf8d02` (con T3a).
- **Implementó:** el engineer, en su worktree aislado (`.claude/worktrees/agent-a875daf2dcf8b2484`). Es la primera corrida con el arreglo de T3a: hizo `git switch` a la rama y escribió sin bloqueos. Commits como `talos-bot-leon`.
- **Pruebas de aceptación:** las escribió el test-writer (`bd3f31d`, 44 casos).
- **Diff:** unas 2600 líneas, más de la guía de 400. Son sobre todo el script (808 líneas) y las dos suites (838 y 644); los criterios pidieron cobertura por caso.

## Commits

1. `716b8c3` docs(T3b): criterios.
2. `bd3f31d` test(T3b): 44 casos de aceptación. Antes de la implementación: `5 ok, 39 fallos`. Los 5 ok son invariantes que el instalador debe mantener: no llamar a `gh` ni a `railway`, no tocar el remoto y no hacer commits.
3. `4d817ad`, `655322e`, `6ebc1f8`, `c3f28ba`, `4fbd3aa` feat(T3b): manifiesto, plantillas, `instalar.sh`, rendimiento y rutas con comillas, `package.json` sin dependencias y pruebas unitarias. `4d817ad` salió sin las líneas de atribución, y no se reescribió.
4. **Bloqueo del engineer:** 4 pruebas de aceptación no podían pasar con ninguna implementación. Terminaban en `A && { ...; return 1; }` sin `return 0`. El engineer creó `.pipeline/BLOCKED` con el diagnóstico, el CTO lo confirmó y el test-writer agregó los 4 `return 0` en `76b7fcd`. Ninguna aserción cambió.
5. `e4fe3d2` feat(T3b): ajustes del CTO en los pasos manuales.
   - **Protección en tres pasos por rama.** Primero el PUT con `contexts`, que la documentación de GitHub marca como obligatorio, en retiro, y que es la forma de su ejemplo. Después el PATCH de `required_status_checks` con `checks` y `app_id` 15368, que Leonardo ya corrió con éxito en este repo en el paso e. Al final, el GET.
   - **Nota del SDK de Railway.** `npm install` crea `package.json` en la raíz, y en un proyecto que no es de Node eso cambia qué pruebas corren el CI y el hook Stop.

## Tests

- `npm test --silent` sale con 0 en Git Bash para Windows.
  - `bash tests/acceptance/test-instalador.sh`: `44 ok, 0 fallos`, en unos 1 min 35 s.
  - `bash tests/unit/test-instalar.sh`: `118 ok, 0 fallos`, en unos 45 s.
- `npm ci` funciona con el lockfile, que no tiene dependencias.

## Decisiones del engineer fuera de la letra de los criterios (para el auditor)

- **Detección de modo.** Ignora las rutas del manifiesto y las generadas. Así, una segunda corrida después de commitear el framework sigue en `modo nuevo`, con todo `igual`. Con la regla literal de C5, esa corrida daría conflicto en `plan.json`.
- **`staging` en el remoto.** Si existe `origin/staging` y no hay una `staging` local, se informa `rama staging: existe` y no se crea.
- **`railway.ts`.** Lleva `export const partial = '<repo>'`, como la salida en seco de `railway config migrate` de la CLI 5.62.1, para que `config apply` administre solo lo declarado. La forma de `service()` y de `deploy` se verificó contra los tipos del paquete `railway@3.11.0`.
- **Fin de línea.** Un archivo generado que solo difiere en CRLF cuenta como `igual`.
- **Diff de un generado en conflicto.** Se imprime contra el contenido generado (`diff - <destino> <<'GENERADO'`).
- **Validaciones y códigos de salida.** Código 2 para: `--servicio` fuera de `[A-Za-z0-9._-]`, `--puerto` fuera de 1 a 65535, un destino que no es la raíz del repo o que es la propia fuente. Acepta `--opcion=valor` y `--`. Código 1 para una fuente inválida o una escritura que falla.
- **`origin`.** Su URL nunca se imprime, porque podría traer credenciales. Sin `origin` de GitHub, el dueño sale de `pipeline.conf` y el repo del nombre de la carpeta. Si el dueño del destino es otro, se imprime una nota para ajustar `pipeline.conf` y `CODEOWNERS`.
- **Portabilidad.** git corre con `cd` al destino, no con `git -C`, por la conversión de rutas de Git Bash.

## Riesgos que no tocan los criterios, para Leonardo

- **`SETUP.md` en los repos instalados.** `scripts/test-hooks.sh` (línea 818) exige `SETUP.md`, y C2 prohíbe copiarlo. En un repo instalado, el job `hooks` del CI fallaría. Hace falta un cambio de gobierno en la suite o en el manifiesto.
- **Tiempo del hook Stop.** En Windows, `npm test` completo tarda unos 2 min 20 s y puede pasarse del tiempo límite del hook Stop.
