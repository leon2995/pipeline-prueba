# Criterios: T1 (ADR del stack actual)

Riesgo: **bajo**. Solo documenta el stack que el repo ya tiene: no cambia código, configuración ni dependencias.

Archivo esperado: `docs/adr/0001-stack-actual.md`, con las secciones de `docs/adr/0000-plantilla.md`.

Pistas: manifiestos que detectó el instalador en los archivos versionados del repo. Son el punto de partida, no la lista completa.
{{manifiestos}}

## Criterios

- **C1. El ADR existe y sigue la plantilla.** `docs/adr/0001-stack-actual.md` existe y tiene las secciones de `docs/adr/0000-plantilla.md` (Contexto, Decisión, Alternativas descartadas, Consecuencias y Aprobación), con fecha y estado.
- **C2. Stack con la fuente de cada dato.** Nombra el lenguaje y su versión, el runtime, el framework principal y el gestor de paquetes, y cita para cada dato el archivo y la clave o la línea de donde sale. Cubre, como mínimo, cada manifiesto de las pistas.
- **C3. Comandos reales.** Dice cómo se instalan las dependencias, cómo se corren las pruebas, cómo se construye y cómo se arranca la app, con los comandos que definen los manifiestos, el CI o el `Dockerfile`. Cada comando se verificó corriéndolo o se cita del archivo que lo define; lo que no existe se dice ("no hay pruebas").
- **C4. Integraciones y variables.** Lista los servicios externos (bases de datos, colas, APIs de terceros) y las variables de entorno que lee el código, solo por nombre y nunca con su valor, con el archivo donde se leen. Los mismos nombres quedan en `.pipeline/variables-requeridas.txt`.
- **C5. Sin cambios de código.** El diff solo agrega `docs/adr/0001-stack-actual.md` y archivos de `.pipeline/`.
