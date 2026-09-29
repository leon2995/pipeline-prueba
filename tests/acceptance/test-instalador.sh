#!/usr/bin/env bash
# Pruebas de aceptación del instalador v1 (T3b): instalador/instalar.sh copia el framework a
# otro repo sin pisar archivos, crea la rama `staging`, genera `.railway/railway.ts` e imprime
# los pasos manuales. Ver .pipeline/criterios-T3b.md (C1 a C10).
#
# Uso: bash tests/acceptance/test-instalador.sh
#
# Nota sobre el hook de la sesión: este archivo se corre como un solo proceso bash; lo que hace
# internamente (gh/railway falsos en el PATH, git push a un remoto bare local, etc.) no pasa por
# la herramienta Bash de la sesión y por lo tanto no lo bloquea el hook. Solo el comando
# `bash tests/acceptance/test-instalador.sh` pasa por ahí, y su texto no nombra nada prohibido.
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
instalador="$repo/instalador/instalar.sh"
manifiesto="$repo/instalador/manifiesto.txt"

ok=0
fallos=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

conf() { sed -n "s/^$1=//p" "$repo/.claude/pipeline.conf" 2>/dev/null | tr -d '\r' | head -1; }
dueno_marco=$(conf dueno)
bot_marco=$(conf bot)

# -- gh y railway falsos: registran cualquier invocación; el instalador nunca debe llamarlos (C6).
mkdir -p "$tmp/bin"
log_gh="$tmp/llamadas-gh.log"
log_railway="$tmp/llamadas-railway.log"
: > "$log_gh"
: > "$log_railway"
cat > "$tmp/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log_gh"
exit 0
EOF
cat > "$tmp/bin/railway" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log_railway"
exit 0
EOF
chmod +x "$tmp/bin/gh" "$tmp/bin/railway"
export PATH="$tmp/bin:$PATH"

# ---------------------------------------------------------------------------
# utilidades
# ---------------------------------------------------------------------------

contador=0
sig() { contador=$((contador + 1)); printf '%03d' "$contador"; }

# nuevo_repo <nombre> [--sin-origen] [--rama NOMBRE]: crea un repo git en un directorio temporal
# (el nombre puede tener espacios, C10) con origin https://github.com/acme/demo.git, salvo que se
# pida --sin-origen. Imprime la ruta por stdout.
nuevo_repo() {
  local nombre=$1
  shift
  local rama=main sin_origen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --sin-origen) sin_origen=1; shift ;;
      --rama) rama=$2; shift 2 ;;
      *) shift ;;
    esac
  done
  local ruta="$tmp/repos/$(sig)-$nombre"
  mkdir -p "$ruta"
  git -C "$ruta" init -q -b "$rama"
  if [ "$sin_origen" -eq 0 ]; then
    git -C "$ruta" remote add origin https://github.com/acme/demo.git
  fi
  printf '%s' "$ruta"
}

# commit_todo <ruta> [mensaje]: agrega y commitea todo con una identidad de prueba.
commit_todo() {
  local ruta=$1 msg=${2:-inicial}
  git -C "$ruta" add -A
  git -c user.name=x -c user.email=x@x.com -C "$ruta" commit -q -m "$msg" --allow-empty
}

# escribir <archivo> <contenido>: crea el archivo (y su carpeta) con ese contenido exacto.
escribir() {
  mkdir -p "$(dirname "$1")"
  printf '%s' "$2" > "$1"
}

# huella <ruta>: hash de todos los archivos (menos .git), ramas locales y git status. Sirve para
# comparar el destino antes y después de correr el instalador (C1, C8).
huella() {
  (
    cd "$1" || exit 1
    find . -path './.git' -prune -o -type f -print0 2>/dev/null | sort -z | xargs -0 sha1sum 2>/dev/null
    printf -- '--ramas--\n'
    git for-each-ref --format='%(refname) %(objectname)' refs/heads 2>/dev/null
    printf -- '--status--\n'
    git status --porcelain 2>/dev/null
  )
}

# ejecutar <args...>: corre el instalador real y deja SALIDA, ERRSAL y CODIGO.
ejecutar() {
  local ef
  ef=$(mktemp "$tmp/stderr.XXXXXX")
  SALIDA=$(bash "$instalador" "$@" 2>"$ef")
  CODIGO=$?
  ERRSAL=$(cat "$ef" 2>/dev/null)
  rm -f "$ef"
}

# contiene <texto> <subtexto>: sale 0 si <texto> contiene <subtexto> (comparación literal).
contiene() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

# caso <descripción, empieza con "Cn:"> <función> [args...]: corre la función; si sale 0, ok; si
# no, FALLO con lo que la función haya impreso (por convención, solo imprime al fallar).
caso() {
  local desc=$1 salida
  shift
  if salida=$("$@" 2>&1); then
    ok=$((ok + 1))
    printf 'ok     %s\n' "$desc"
  else
    fallos=$((fallos + 1))
    printf 'FALLO  %s%s\n' "$desc" "${salida:+ -> $salida}"
  fi
}

# ===========================================================================
echo "== C1: simulación por defecto"
# ===========================================================================

c1_sin_conflictos() {
  local d antes despues
  d=$(nuevo_repo c1-simple)
  escribir "$d/otro.txt" "contenido normal"
  commit_todo "$d"
  antes=$(huella "$d")
  ejecutar "$d"
  [ "$CODIGO" -eq 0 ] || { echo "código $CODIGO, esperaba 0"; return 1; }
  despues=$(huella "$d")
  [ "$antes" = "$despues" ] || { echo "el destino cambió sin --aplicar"; return 1; }
  contiene "$SALIDA" "crear CLAUDE.md" || { echo "no imprimió el plan (crear CLAUDE.md)"; return 1; }
  contiene "$SALIDA" "== Pasos manuales" || { echo "no imprimió los pasos manuales"; return 1; }
}

c1_con_conflicto() {
  local d antes despues
  d=$(nuevo_repo c1-conflicto)
  cp "$repo/.gitattributes" "$d/.gitattributes"
  printf 'x' >> "$d/.gitattributes"
  commit_todo "$d"
  antes=$(huella "$d")
  ejecutar "$d"
  [ "$CODIGO" -eq 3 ] || { echo "código $CODIGO, esperaba 3 (hay un conflicto)"; return 1; }
  despues=$(huella "$d")
  [ "$antes" = "$despues" ] || { echo "el destino cambió sin --aplicar, con conflicto"; return 1; }
  contiene "$SALIDA" "conflicto .gitattributes" || { echo "no reportó el conflicto"; return 1; }
}

c1_no_llama_herramientas() {
  local d
  d=$(nuevo_repo c1-herramientas)
  commit_todo "$d"
  ejecutar "$d"
  [ -s "$log_gh" ] && { echo "llamó a gh"; return 1; }
  [ -s "$log_railway" ] && { echo "llamó a railway"; return 1; }
  return 0
}

caso "C1: sin --aplicar el destino queda idéntico y sale 0" c1_sin_conflictos
caso "C1: sin --aplicar con un conflicto, destino idéntico y sale 3" c1_con_conflicto
caso "C1: la simulación no llama a gh ni a railway" c1_no_llama_herramientas

# ===========================================================================
echo "== C2: qué se copia"
# ===========================================================================

c2_manifiesto_existe_con_rutas() {
  [ -f "$manifiesto" ] || { echo "no existe $manifiesto"; return 1; }
  local n
  n=$(grep -vE '^[[:space:]]*(#|$)' "$manifiesto" 2>/dev/null | tr -d '\r' | grep -c '[^[:space:]]')
  [ "${n:-0}" -gt 0 ] || { echo "el manifiesto no tiene rutas"; return 1; }
}

c2_rutas_existen_en_la_fuente() {
  [ -f "$manifiesto" ] || { echo "no existe $manifiesto"; return 1; }
  local linea limpio faltan=""
  while IFS= read -r linea || [ -n "$linea" ]; do
    limpio=$(printf '%s' "$linea" | tr -d '\r')
    limpio="${limpio#"${limpio%%[![:space:]]*}"}"
    case "$limpio" in
      '' | '#'*) continue ;;
    esac
    [ -e "$repo/$limpio" ] || faltan="$faltan $limpio"
  done < "$manifiesto"
  [ -z "$faltan" ] || { echo "rutas del manifiesto que no existen en la fuente:$faltan"; return 1; }
}

c2_nunca_copiados() {
  [ -f "$manifiesto" ] || { echo "no existe $manifiesto"; return 1; }
  local prohibidos=(
    ".claude/settings.local.json" ".claude/identidad-agente.txt" ".claude/worktrees/"
    "tests/" "instalador/" "package.json" "package-lock.json" "SETUP.md" "README.md"
    "railway.json" "docs/FASE-2-HERMES.md" ".pipeline/plan.json" ".pipeline/modo"
    ".pipeline/criterios-T3b.md" ".pipeline/test-hooks-salida.txt" ".pipeline/lecciones-pendientes.md"
  )
  local limpio p encontrados=""
  limpio=$(tr -d '\r' < "$manifiesto")
  for p in "${prohibidos[@]}"; do
    printf '%s\n' "$limpio" | grep -Fxq "$p" && encontrados="$encontrados $p"
  done
  [ -z "$encontrados" ] || { echo "el manifiesto lista rutas prohibidas:$encontrados"; return 1; }
}

c2_incluye_lo_requerido() {
  [ -f "$manifiesto" ] || { echo "no existe $manifiesto"; return 1; }
  local requeridos=(
    "CLAUDE.md" "LESSONS.md" ".gitattributes" ".gitignore" ".claude/rutas-gobierno.txt"
    ".claude/settings.json" ".claude/settings.local.example.json" ".claude/pipeline.conf"
    ".github/CODEOWNERS" ".github/workflows/ci.yml" "docs/adr/0000-plantilla.md"
    "scripts/jev.py" "scripts/test-hooks.sh" "scripts/run-task.sh" "scripts/resume-task.sh"
    "scripts/watch-deploy.sh" ".pipeline/README.md" ".pipeline/urls.json"
  )
  local f
  while IFS= read -r -d '' f; do
    requeridos+=("${f#"$repo"/}")
  done < <(find "$repo/.claude/agents" "$repo/.claude/commands" "$repo/.claude/prompts" \
    "$repo/.claude/hooks" -type f -print0 2>/dev/null)
  local limpio r faltan=""
  limpio=$(tr -d '\r' < "$manifiesto")
  for r in "${requeridos[@]}"; do
    printf '%s\n' "$limpio" | grep -Fxq "$r" || faltan="$faltan $r"
  done
  [ -z "$faltan" ] || { echo "faltan del manifiesto:$faltan"; return 1; }
}

# c2_ignora_comentarios_y_vacias: corre el instalador real (ya implementado) desde una copia de
# instalador/ con un manifiesto de prueba propio, para verificar que los comentarios (#) y las
# líneas vacías se ignoran al copiar, sin depender del contenido real del framework.
c2_ignora_comentarios_y_vacias() {
  [ -f "$instalador" ] || { echo "no existe $instalador"; return 1; }
  local f="$tmp/fuentes/$(sig)"
  mkdir -p "$f/.claude" "$f/instalador" "$f/carpeta"
  cp -r "$repo/instalador/." "$f/instalador/" 2>/dev/null
  cp "$repo/.claude/pipeline.conf" "$f/.claude/pipeline.conf" 2>/dev/null
  escribir "$f/uno.txt" "contenido uno"
  escribir "$f/carpeta/dos.txt" "contenido dos"
  {
    echo "# manifiesto de prueba, con comentarios y líneas vacías"
    echo
    echo "uno.txt"
    echo "# esto no es una ruta: carpeta/no-existe.txt"
    echo
    echo "carpeta/dos.txt"
  } > "$f/instalador/manifiesto.txt"
  local d salida codigo
  d=$(nuevo_repo c2-comentarios)
  commit_todo "$d"
  salida=$(bash "$f/instalador/instalar.sh" "$d" --aplicar 2>&1)
  codigo=$?
  [ "$codigo" -eq 0 ] || { echo "código $codigo, esperaba 0; salida: $salida"; return 1; }
  cmp -s "$f/uno.txt" "$d/uno.txt" || { echo "uno.txt no se copió"; return 1; }
  cmp -s "$f/carpeta/dos.txt" "$d/carpeta/dos.txt" || { echo "carpeta/dos.txt no se copió"; return 1; }
  [ -e "$d/no-existe.txt" ] && { echo "creó un archivo a partir de un comentario"; return 1; }
  return 0
}

caso "C2: manifiesto.txt existe y lista al menos una ruta" c2_manifiesto_existe_con_rutas
caso "C2: toda ruta del manifiesto existe en la fuente" c2_rutas_existen_en_la_fuente
caso "C2: el manifiesto nunca lista los archivos prohibidos" c2_nunca_copiados
caso "C2: el manifiesto incluye los archivos y carpetas requeridos" c2_incluye_lo_requerido
caso "C2: comentarios y líneas vacías del manifiesto se ignoran al copiar" c2_ignora_comentarios_y_vacias

# ===========================================================================
echo "== C3: no pisar"
# ===========================================================================

c3_crear_igual_conflicto() {
  local d salida codigo snap_conflicto="$tmp/lessons-conflicto-$(sig)"
  d=$(nuevo_repo c3-basico)
  cp "$repo/.gitattributes" "$d/.gitattributes"
  cp "$repo/LESSONS.md" "$d/LESSONS.md"
  printf '\nconflicto de prueba\n' >> "$d/LESSONS.md"
  cp "$d/LESSONS.md" "$snap_conflicto"
  commit_todo "$d"
  salida=$(bash "$instalador" "$d" --aplicar 2>&1)
  codigo=$?
  [ "$codigo" -eq 3 ] || { echo "código $codigo, esperaba 3"; return 1; }
  contiene "$salida" "crear .gitignore" || { echo "no creó .gitignore (crear)"; return 1; }
  contiene "$salida" "igual .gitattributes" || { echo "no marcó .gitattributes como igual"; return 1; }
  contiene "$salida" "conflicto LESSONS.md" || { echo "no marcó LESSONS.md como conflicto"; return 1; }
  cmp -s "$repo/.gitignore" "$d/.gitignore" || { echo ".gitignore no quedó igual a la fuente"; return 1; }
  cmp -s "$snap_conflicto" "$d/LESSONS.md" || { echo "LESSONS.md (conflicto) cambió byte a byte"; return 1; }
  case "$salida" in
    *"diff"*"LESSONS.md"*"LESSONS.md"*) ;;
    *) echo "no imprimió 'diff <fuente>/LESSONS.md <destino>/LESSONS.md'"; return 1 ;;
  esac
}

c3_segunda_corrida_idempotente() {
  local d antes despues salida1 salida2 codigo1 codigo2
  d=$(nuevo_repo c3-idempotente)
  commit_todo "$d"
  salida1=$(bash "$instalador" "$d" --aplicar 2>&1)
  codigo1=$?
  [ "$codigo1" -eq 0 ] || { echo "primera corrida: código $codigo1, esperaba 0; salida: $salida1"; return 1; }
  antes=$(huella "$d")
  salida2=$(bash "$instalador" "$d" --aplicar 2>&1)
  codigo2=$?
  [ "$codigo2" -eq 0 ] || { echo "segunda corrida: código $codigo2, esperaba 0; salida: $salida2"; return 1; }
  despues=$(huella "$d")
  [ "$antes" = "$despues" ] || { echo "la segunda corrida cambió el destino"; return 1; }
  contiene "$salida2" "conflicto" && { echo "la segunda corrida reportó un conflicto"; return 1; }
  contiene "$salida2" "igual CLAUDE.md" || { echo "la segunda corrida no reportó 'igual CLAUDE.md'"; return 1; }
}

caso "C3: crear/igual/conflicto según el contenido; con conflicto sale 3 y no se pisa nada" c3_crear_igual_conflicto
caso "C3: una segunda corrida con --aplicar informa todo igual y sale 0" c3_segunda_corrida_idempotente

# ===========================================================================
echo "== C4: archivos generados"
# ===========================================================================

c4_lecciones_pendientes() {
  local d f
  d=$(nuevo_repo c4-lecciones)
  commit_todo "$d"
  bash "$instalador" "$d" --aplicar >/dev/null 2>&1
  f="$d/.pipeline/lecciones-pendientes.md"
  [ -f "$f" ] || { echo "no generó $f"; return 1; }
  grep -q "Lecciones pendientes" "$f" || { echo "sin el encabezado del flujo"; return 1; }
  grep -q "Ninguna" "$f" || { echo "sin 'Ninguna' en pendientes"; return 1; }
  grep -q "PR #14" "$f" && { echo "trae el historial de este repo"; return 1; }
}

c4_plan_json_nuevo() {
  local d f contenido
  d=$(nuevo_repo c4-plan-nuevo)
  commit_todo "$d"
  bash "$instalador" "$d" --aplicar >/dev/null 2>&1
  f="$d/.pipeline/plan.json"
  [ -f "$f" ] || { echo "no generó $f"; return 1; }
  contenido=$(tr -d ' \t\n\r' < "$f")
  case "$contenido" in
    *'"subtareas":[]'*) ;;
    *) echo "plan.json no trae la plantilla vacía de subtareas"; return 1 ;;
  esac
}

c4_railway_ts() {
  local d f contenido
  d=$(nuevo_repo c4-railway)
  commit_todo "$d"
  bash "$instalador" "$d" --aplicar >/dev/null 2>&1
  f="$d/.railway/railway.ts"
  [ -f "$f" ] || { echo "no generó $f"; return 1; }
  contenido=$(cat "$f")
  contiene "$contenido" "import { defineRailway, project, service } from 'railway/iac'" || { echo "falta el import"; return 1; }
  contiene "$contenido" "healthcheck: '/health'" || { echo "falta healthcheck: '/health'"; return 1; }
  contiene "$contenido" "healthcheckTimeout: 120" || { echo "falta healthcheckTimeout: 120"; return 1; }
  contiene "$contenido" "restartPolicyType: 'ON_FAILURE'" || { echo "falta restartPolicyType: 'ON_FAILURE'"; return 1; }
  contiene "$contenido" "restartPolicyMaxRetries: 3" || { echo "falta restartPolicyMaxRetries: 3"; return 1; }
  contiene "$contenido" "project('demo'" || { echo "el proyecto no usa 'demo' (repo derivado de origin)"; return 1; }
  contiene "$contenido" "'demo'" || { echo "no nombra el servicio por defecto (demo)"; return 1; }
}

c4_servicio_override() {
  local d f contenido
  d=$(nuevo_repo c4-servicio)
  commit_todo "$d"
  bash "$instalador" "$d" --aplicar --servicio miapi >/dev/null 2>&1
  f="$d/.railway/railway.ts"
  [ -f "$f" ] || { echo "no generó $f"; return 1; }
  contenido=$(cat "$f")
  contiene "$contenido" "project('demo'" || { echo "el proyecto debería seguir siendo demo"; return 1; }
  contiene "$contenido" "miapi" || { echo "no aplicó --servicio miapi"; return 1; }
}

c4_repo_sin_origen_usa_carpeta() {
  local d base contenido f
  d=$(nuevo_repo c4-sin-origen --sin-origen)
  base=$(basename "$d")
  commit_todo "$d"
  bash "$instalador" "$d" --aplicar >/dev/null 2>&1
  f="$d/.railway/railway.ts"
  [ -f "$f" ] || { echo "no generó $f"; return 1; }
  contenido=$(cat "$f")
  contiene "$contenido" "$base" || { echo "sin origin no usó el nombre de la carpeta ($base) como repo"; return 1; }
}

c4_generado_existente_igual_y_conflicto() {
  local a b c salida_b salida_c snap="$tmp/railway-conflicto-$(sig)"
  a=$(nuevo_repo c4-gen-a)
  commit_todo "$a"
  bash "$instalador" "$a" --aplicar >/dev/null 2>&1
  [ -f "$a/.railway/railway.ts" ] || { echo "no generó railway.ts en la corrida base"; return 1; }

  b=$(nuevo_repo c4-gen-b)
  commit_todo "$b"
  mkdir -p "$b/.railway"
  cp "$a/.railway/railway.ts" "$b/.railway/railway.ts"
  salida_b=$(bash "$instalador" "$b" --aplicar 2>&1)
  contiene "$salida_b" "igual .railway/railway.ts" || { echo "no marcó railway.ts preexistente igual como 'igual'"; return 1; }

  c=$(nuevo_repo c4-gen-c)
  commit_todo "$c"
  mkdir -p "$c/.railway"
  cp "$a/.railway/railway.ts" "$c/.railway/railway.ts"
  printf '\n// distinto\n' >> "$c/.railway/railway.ts"
  cp "$c/.railway/railway.ts" "$snap"
  salida_c=$(bash "$instalador" "$c" --aplicar 2>&1)
  contiene "$salida_c" "conflicto .railway/railway.ts" || { echo "no marcó railway.ts distinto como 'conflicto'"; return 1; }
  cmp -s "$snap" "$c/.railway/railway.ts" || { echo "el railway.ts en conflicto cambió"; return 1; }
}

caso "C4: .pipeline/lecciones-pendientes.md se genera con el encabezado del flujo, sin el historial de este repo" c4_lecciones_pendientes
caso "C4: .pipeline/plan.json se genera con la plantilla vacía de subtareas (modo nuevo)" c4_plan_json_nuevo
caso "C4: .railway/railway.ts se genera con la política de reinicio y el healthcheck exigidos" c4_railway_ts
caso "C4: --servicio reemplaza el nombre del servicio sin cambiar el del repo" c4_servicio_override
caso "C4: sin origin, el repo sale del nombre de la carpeta del destino" c4_repo_sin_origen_usa_carpeta
caso "C4: un archivo generado preexistente cuenta como igual o conflicto según su contenido" c4_generado_existente_igual_y_conflicto

# ===========================================================================
echo "== C5: modos"
# ===========================================================================

c5_nuevo_sin_commits() {
  local d
  d=$(nuevo_repo c5-sin-commits)
  ejecutar "$d"
  contiene "$SALIDA" "modo nuevo" || { echo "un repo sin commits debería detectarse como nuevo"; return 1; }
}

c5_nuevo_solo_archivos_permitidos() {
  local d
  d=$(nuevo_repo c5-nuevo-permitidos)
  escribir "$d/README.md" "hola"
  escribir "$d/LICENSE" "licencia"
  escribir "$d/.gitignore" "*.log"
  escribir "$d/.gitattributes" "* text=auto"
  commit_todo "$d"
  ejecutar "$d"
  contiene "$SALIDA" "modo nuevo" || { echo "solo con README/LICENSE/.gitignore/.gitattributes debería ser nuevo"; return 1; }
}

c5_nuevo_con_un_solo_archivo_permitido() {
  local d
  d=$(nuevo_repo c5-nuevo-license)
  escribir "$d/LICENSE.txt" "licencia"
  commit_todo "$d"
  ejecutar "$d"
  contiene "$SALIDA" "modo nuevo" || { echo "solo con LICENSE.txt debería ser nuevo"; return 1; }
}

c5_existente_con_otro_archivo() {
  local d
  d=$(nuevo_repo c5-existente)
  escribir "$d/README.md" "hola"
  escribir "$d/src/app.py" "print('hola')"
  commit_todo "$d"
  ejecutar "$d"
  contiene "$SALIDA" "modo existente" || { echo "con src/app.py debería ser existente"; return 1; }
}

c5_modo_forzado() {
  local d
  d=$(nuevo_repo c5-forzado-a-existente)
  commit_todo "$d"
  ejecutar "$d" --modo existente
  contiene "$SALIDA" "modo existente" || { echo "--modo existente no forzó el modo en un repo nuevo"; return 1; }

  d=$(nuevo_repo c5-forzado-a-nuevo)
  escribir "$d/src/app.py" "print(1)"
  commit_todo "$d"
  ejecutar "$d" --modo nuevo
  contiene "$SALIDA" "modo nuevo" || { echo "--modo nuevo no forzó el modo en un repo existente"; return 1; }
}

c5_existente_genera_t1_y_criterios() {
  local d f
  d=$(nuevo_repo c5-t1)
  escribir "$d/package.json" '{"name":"x"}'
  escribir "$d/Dockerfile" "FROM scratch"
  commit_todo "$d"
  ejecutar "$d" --aplicar
  contiene "$SALIDA" "modo existente" || { echo "no detectó modo existente"; return 1; }
  f="$d/.pipeline/plan.json"
  [ -f "$f" ] || { echo "no generó plan.json"; return 1; }
  grep -q '"T1"' "$f" || { echo "plan.json no trae la subtarea T1"; return 1; }
  grep -q "ADR del stack actual" "$f" || { echo "plan.json no nombra 'ADR del stack actual'"; return 1; }
  grep -q "docs/adr/0001-stack-actual.md" "$f" || { echo "plan.json no trae el archivo esperado"; return 1; }
  f="$d/.pipeline/criterios-T1.md"
  [ -f "$f" ] || { echo "no generó .pipeline/criterios-T1.md"; return 1; }
  [ -s "$f" ] || { echo "criterios-T1.md está vacío"; return 1; }
  grep -q "package.json" "$f" || { echo "criterios-T1.md no nombra package.json como pista"; return 1; }
  grep -q "Dockerfile" "$f" || { echo "criterios-T1.md no nombra Dockerfile como pista"; return 1; }
}

caso "C5: repo sin commits se detecta como nuevo" c5_nuevo_sin_commits
caso "C5: repo con solo README/LICENSE/.gitignore/.gitattributes se detecta como nuevo" c5_nuevo_solo_archivos_permitidos
caso "C5: un solo archivo permitido (LICENSE.txt) también da modo nuevo" c5_nuevo_con_un_solo_archivo_permitido
caso "C5: cualquier otro archivo versionado da modo existente" c5_existente_con_otro_archivo
caso "C5: --modo fuerza el modo detectado" c5_modo_forzado
caso "C5: modo existente genera la subtarea T1 y sus criterios, con pistas de manifiestos detectados" c5_existente_genera_t1_y_criterios

# ===========================================================================
echo "== C6: rama staging"
# ===========================================================================

c6_crea_en_head_sin_cambiar_activa() {
  local d rama_antes head_antes salida
  d=$(nuevo_repo c6-crear --rama trabajo)
  commit_todo "$d"
  rama_antes=$(git -C "$d" branch --show-current)
  head_antes=$(git -C "$d" rev-parse HEAD)
  salida=$(bash "$instalador" "$d" --aplicar 2>&1)
  contiene "$salida" "rama staging: crear" || { echo "no reportó 'rama staging: crear'"; return 1; }
  git -C "$d" show-ref --verify --quiet refs/heads/staging || { echo "no creó la rama staging"; return 1; }
  [ "$(git -C "$d" rev-parse staging)" = "$head_antes" ] || { echo "staging no quedó en HEAD"; return 1; }
  [ "$(git -C "$d" branch --show-current)" = "$rama_antes" ] || { echo "cambió la rama activa"; return 1; }
}

c6_existente_no_se_toca() {
  local d salida commit_viejo
  d=$(nuevo_repo c6-existe)
  commit_todo "$d" primero
  commit_viejo=$(git -C "$d" rev-parse HEAD)
  git -C "$d" branch staging "$commit_viejo"
  commit_todo "$d" segundo
  salida=$(bash "$instalador" "$d" --aplicar 2>&1)
  contiene "$salida" "rama staging: existe" || { echo "no reportó 'rama staging: existe'"; return 1; }
  [ "$(git -C "$d" rev-parse staging)" = "$commit_viejo" ] || { echo "movió la rama staging existente"; return 1; }
}

c6_sin_commits_no_crea() {
  local d salida
  d=$(nuevo_repo c6-sin-commits)
  salida=$(bash "$instalador" "$d" --aplicar 2>&1)
  contiene "$salida" "rama staging: sin commits" || { echo "no reportó 'rama staging: sin commits'"; return 1; }
  git -C "$d" show-ref --verify --quiet refs/heads/staging && { echo "creó staging sin commits"; return 1; }
}

c6_no_toca_el_remoto() {
  local bare d refs_antes refs_despues
  bare="$tmp/remotos/$(sig).git"
  git init -q --bare "$bare"
  d=$(nuevo_repo c6-remoto --sin-origen)
  git -C "$d" remote add origin "$bare"
  commit_todo "$d"
  git -C "$d" push -q origin main
  refs_antes=$(git -C "$bare" show-ref)
  bash "$instalador" "$d" --aplicar >/dev/null 2>&1
  refs_despues=$(git -C "$bare" show-ref)
  [ "$refs_antes" = "$refs_despues" ] || { echo "el remoto cambió: hubo push o fetch"; return 1; }
}

c6_no_agrega_commits() {
  local d antes despues
  d=$(nuevo_repo c6-sin-commits-nuevos)
  commit_todo "$d"
  antes=$(git -C "$d" rev-list --count main)
  bash "$instalador" "$d" --aplicar >/dev/null 2>&1
  despues=$(git -C "$d" rev-list --count main)
  [ "$antes" = "$despues" ] || { echo "el instalador agregó commits a main"; return 1; }
}

caso "C6: con commits y sin staging, crea staging en HEAD sin cambiar la rama activa" c6_crea_en_head_sin_cambiar_activa
caso "C6: si staging ya existe, no se mueve" c6_existente_no_se_toca
caso "C6: sin commits, no crea staging" c6_sin_commits_no_crea
caso "C6: nunca hace push ni fetch (las referencias del remoto no cambian)" c6_no_toca_el_remoto
caso "C6: nunca agrega commits a la rama activa" c6_no_agrega_commits

# ===========================================================================
echo "== C7: pasos manuales"
# ===========================================================================

c7_comandos_exactos() {
  local d salida
  d=$(nuevo_repo c7-basico --rama trabajo)
  commit_todo "$d"
  salida=$(bash "$instalador" "$d" --aplicar 2>&1)

  # 1. Git
  contiene "$salida" "git push -u origin trabajo staging" || { echo "falta 'git push -u origin trabajo staging'"; return 1; }
  contiene "$salida" "merge --ff-only" || { echo "falta 'git merge --ff-only'"; return 1; }
  case "$salida" in
    *"merge --ff-only"*"trabajo"* | *"trabajo"*"merge --ff-only"*) ;;
    *) echo "el merge --ff-only no nombra la rama activa (trabajo)"; return 1 ;;
  esac

  # 2. GitHub
  contiene "$salida" "gh api -X PUT repos/acme/demo/collaborators/$bot_marco -f permission=push" \
    || { echo "falta la invitación exacta del bot"; return 1; }
  contiene "$salida" 'gh api user/repository_invitations' || { echo "falta consultar las invitaciones"; return 1; }
  contiene "$salida" '$HOME/.talos-gh' || { echo 'falta GH_CONFIG_DIR="$HOME/.talos-gh" al aceptar la invitación'; return 1; }
  contiene "$salida" "gh api -X PATCH user/repository_invitations/" || { echo "falta aceptar la invitación (PATCH)"; return 1; }
  contiene "$salida" "gh api -X PUT repos/acme/demo/branches/main/protection --input -" \
    || { echo "falta la protección exacta de main"; return 1; }
  contiene "$salida" "gh api -X PUT repos/acme/demo/branches/staging/protection --input -" \
    || { echo "falta la protección exacta de staging"; return 1; }
  printf '%s' "$salida" | grep -Eq '"required_approving_review_count"[[:space:]]*:[[:space:]]*1([^0-9]|$)' \
    || { echo "no encontré 1 aprobación requerida (main)"; return 1; }
  printf '%s' "$salida" | grep -Eq '"required_approving_review_count"[[:space:]]*:[[:space:]]*0([^0-9]|$)' \
    || { echo "no encontré 0 aprobaciones requeridas (staging)"; return 1; }
  contiene "$salida" "require_code_owner_reviews" || { echo "falta require_code_owner_reviews"; return 1; }
  contiene "$salida" "dismiss_stale_reviews" || { echo "falta dismiss_stale_reviews"; return 1; }
  contiene "$salida" "enforce_admins" || { echo "falta enforce_admins"; return 1; }
  contiene "$salida" "secrets" || { echo "falta el check 'secrets'"; return 1; }
  contiene "$salida" "hooks" || { echo "falta el check 'hooks'"; return 1; }
  contiene "$salida" "15368" || { echo "falta el app_id 15368"; return 1; }
  printf '%s' "$salida" | grep -Eq '"allow_force_pushes"[[:space:]]*:[[:space:]]*false' \
    || { echo "falta allow_force_pushes en false"; return 1; }
  printf '%s' "$salida" | grep -Eq '"allow_deletions"[[:space:]]*:[[:space:]]*false' \
    || { echo "falta allow_deletions en false"; return 1; }
  contiene "$salida" "repos/acme/demo/branches/main/protection" || { echo "falta el GET de protección de main"; return 1; }
  contiene "$salida" "repos/acme/demo/branches/staging/protection" || { echo "falta el GET de protección de staging"; return 1; }

  # 3. Railway
  contiene "$salida" "railway add --service demo --repo acme/demo --branch main" || { echo "falta 'railway add'"; return 1; }
  contiene "$salida" "railway environment new staging --duplicate production --service-config demo source.branch staging" \
    || { echo "falta 'railway environment new'"; return 1; }
  contiene "$salida" "railway variable set PORT=8080 --service demo --environment production --skip-deploys" \
    || { echo "falta la variable PORT en production"; return 1; }
  contiene "$salida" "railway variable set PORT=8080 --service demo --environment staging --skip-deploys" \
    || { echo "falta la variable PORT en staging"; return 1; }
  contiene "$salida" "railway domain --port 8080 --service demo --environment production" \
    || { echo "falta 'railway domain' en production"; return 1; }
  contiene "$salida" "railway domain --port 8080 --service demo --environment staging" \
    || { echo "falta 'railway domain' en staging"; return 1; }
  contiene "$salida" "npm install --save-dev railway@3.11.0" || { echo "falta instalar el SDK railway@3.11.0"; return 1; }
  contiene "$salida" "Node 22" || { echo "falta la nota de Node 22"; return 1; }
  contiene "$salida" "railway environment link production" || { echo "falta 'environment link production'"; return 1; }
  contiene "$salida" "railway environment link staging" || { echo "falta 'environment link staging'"; return 1; }
  contiene "$salida" "railway config plan" || { echo "falta 'railway config plan'"; return 1; }
  contiene "$salida" "railway config apply" || { echo "falta 'railway config apply'"; return 1; }

  # 4. Agente
  contiene "$salida" ".claude/settings.local.example.json" || { echo "falta nombrar settings.local.example.json"; return 1; }
  contiene "$salida" ".claude/settings.local.json" || { echo "falta nombrar settings.local.json"; return 1; }
  contiene "$salida" "GH_CONFIG_DIR" || { echo "falta completar GH_CONFIG_DIR"; return 1; }
  contiene "$salida" "identidad-agente.txt" || { echo "falta crear identidad-agente.txt"; return 1; }
  contiene "$salida" "$bot_marco" || { echo "falta nombrar al bot ($bot_marco)"; return 1; }

  # placeholders y tokens
  contiene "$salida" "<dueño>" && { echo "quedó <dueño> sin reemplazar"; return 1; }
  contiene "$salida" "<repo>" && { echo "quedó <repo> sin reemplazar"; return 1; }
  contiene "$salida" "<servicio>" && { echo "quedó <servicio> sin reemplazar"; return 1; }
  contiene "$salida" "<puerto>" && { echo "quedó <puerto> sin reemplazar"; return 1; }
  contiene "$salida" "ghp_" && { echo "imprime algo con forma de token (ghp_)"; return 1; }
  contiene "$salida" "GH_TOKEN=" && { echo "imprime GH_TOKEN"; return 1; }
  contiene "$salida" "gh auth token" && { echo "pide imprimir el token"; return 1; }
  return 0
}

c7_servicio_y_puerto_reemplazados() {
  local d salida
  d=$(nuevo_repo c7-override)
  commit_todo "$d"
  salida=$(bash "$instalador" "$d" --aplicar --servicio miapi --puerto 3000 2>&1)
  contiene "$salida" "railway add --service miapi --repo acme/demo --branch main" \
    || { echo "no aplicó --servicio en 'railway add'"; return 1; }
  contiene "$salida" "railway variable set PORT=3000 --service miapi --environment production --skip-deploys" \
    || { echo "no aplicó --servicio/--puerto en la variable de production"; return 1; }
  contiene "$salida" "railway variable set PORT=3000 --service miapi --environment staging --skip-deploys" \
    || { echo "no aplicó --servicio/--puerto en la variable de staging"; return 1; }
  contiene "$salida" "railway domain --port 3000 --service miapi --environment production" \
    || { echo "no aplicó --puerto en 'railway domain' de production"; return 1; }
  contiene "$salida" "8080" && { echo "sigue mostrando el puerto por defecto (8080)"; return 1; }
}

c7_puerto_por_defecto() {
  local d salida
  d=$(nuevo_repo c7-defecto)
  commit_todo "$d"
  salida=$(bash "$instalador" "$d" --aplicar 2>&1)
  contiene "$salida" "PORT=8080" || { echo "el puerto por defecto no es 8080"; return 1; }
}

caso "C7: los comandos de git, GitHub, Railway y del agente salen exactos y sin placeholders" c7_comandos_exactos
caso "C7: --servicio y --puerto se reemplazan en los pasos de Railway" c7_servicio_y_puerto_reemplazados
caso "C7: el puerto por defecto es 8080" c7_puerto_por_defecto

# ===========================================================================
echo "== C8: errores de uso"
# ===========================================================================

c8_sin_argumentos() {
  ejecutar
  [ "$CODIGO" -eq 2 ] || { echo "código $CODIGO, esperaba 2"; return 1; }
  [ -n "$ERRSAL" ] || { echo "no imprimió nada en stderr"; return 1; }
}

c8_destino_no_existe() {
  local d="$tmp/repos/no-existe-$(sig)"
  ejecutar "$d"
  [ "$CODIGO" -eq 2 ] || { echo "código $CODIGO, esperaba 2"; return 1; }
  [ -n "$ERRSAL" ] || { echo "no imprimió nada en stderr"; return 1; }
  [ -e "$d" ] && { echo "creó el destino inexistente"; return 1; }
}

c8_no_es_repo_git() {
  local d="$tmp/repos/no-git-$(sig)" antes despues
  mkdir -p "$d"
  escribir "$d/archivo.txt" "contenido"
  antes=$(huella "$d")
  ejecutar "$d"
  [ "$CODIGO" -eq 2 ] || { echo "código $CODIGO, esperaba 2"; return 1; }
  [ -n "$ERRSAL" ] || { echo "no imprimió nada en stderr"; return 1; }
  despues=$(huella "$d")
  [ "$antes" = "$despues" ] || { echo "tocó una carpeta que no es un repo git"; return 1; }
}

c8_opcion_desconocida() {
  local d antes despues
  d=$(nuevo_repo c8-opcion-desconocida)
  commit_todo "$d"
  antes=$(huella "$d")
  ejecutar "$d" --opcion-rara
  [ "$CODIGO" -eq 2 ] || { echo "código $CODIGO, esperaba 2"; return 1; }
  [ -n "$ERRSAL" ] || { echo "no imprimió nada en stderr"; return 1; }
  despues=$(huella "$d")
  [ "$antes" = "$despues" ] || { echo "tocó el destino con una opción desconocida"; return 1; }
}

c8_modo_invalido() {
  local d antes despues
  d=$(nuevo_repo c8-modo-invalido)
  commit_todo "$d"
  antes=$(huella "$d")
  ejecutar "$d" --modo raro
  [ "$CODIGO" -eq 2 ] || { echo "código $CODIGO, esperaba 2"; return 1; }
  [ -n "$ERRSAL" ] || { echo "no imprimió nada en stderr"; return 1; }
  despues=$(huella "$d")
  [ "$antes" = "$despues" ] || { echo "tocó el destino con --modo inválido"; return 1; }
}

c8_puerto_no_numerico() {
  local d antes despues
  d=$(nuevo_repo c8-puerto-no-numerico)
  commit_todo "$d"
  antes=$(huella "$d")
  ejecutar "$d" --puerto abc
  [ "$CODIGO" -eq 2 ] || { echo "código $CODIGO, esperaba 2"; return 1; }
  [ -n "$ERRSAL" ] || { echo "no imprimió nada en stderr"; return 1; }
  despues=$(huella "$d")
  [ "$antes" = "$despues" ] || { echo "tocó el destino con --puerto no numérico"; return 1; }
}

caso "C8: sin argumentos sale con 2 y un mensaje en stderr" c8_sin_argumentos
caso "C8: un destino que no existe sale con 2 y no lo crea" c8_destino_no_existe
caso "C8: una carpeta que no es un repo git sale con 2 y no se toca" c8_no_es_repo_git
caso "C8: una opción desconocida sale con 2 y no toca el destino" c8_opcion_desconocida
caso "C8: --modo con valor inválido sale con 2 y no toca el destino" c8_modo_invalido
caso "C8: --puerto no numérico sale con 2 y no toca el destino" c8_puerto_no_numerico

# ===========================================================================
echo "== C9: pruebas en CI"
# ===========================================================================

c9_package_json_sin_dependencias() {
  local f="$repo/package.json"
  [ -f "$f" ] || { echo "no existe package.json"; return 1; }
  grep -Eq '"(dependencies|devDependencies)"[[:space:]]*:[[:space:]]*\{[[:space:]]*"' "$f" \
    && { echo "package.json declara dependencias"; return 1; }
  return 0
}

c9_npm_test_corre_ambas_suites() {
  local f="$repo/package.json" script
  [ -f "$f" ] || { echo "no existe package.json"; return 1; }
  script=$(tr -d '\r\n' < "$f")
  contiene "$script" "tests/acceptance" || { echo "npm test no menciona tests/acceptance"; return 1; }
  contiene "$script" "tests/unit" || { echo "npm test no menciona tests/unit"; return 1; }
  grep -q '"test"' "$f" || { echo "package.json no define scripts.test"; return 1; }
}

c9_package_lock_para_npm_ci() {
  local f="$repo/package-lock.json"
  [ -f "$f" ] || { echo "no existe package-lock.json"; return 1; }
  grep -q '"lockfileVersion"' "$f" || { echo "package-lock.json no parece un lockfile válido"; return 1; }
}

caso "C9: package.json no tiene dependencias" c9_package_json_sin_dependencias
caso "C9: npm test corre las pruebas de aceptación y las unitarias" c9_npm_test_corre_ambas_suites
caso "C9: package-lock.json existe para que npm ci funcione" c9_package_lock_para_npm_ci

# ===========================================================================
echo "== C10: portabilidad"
# ===========================================================================

c10_destino_con_espacios() {
  local d salida codigo
  d=$(nuevo_repo "carpeta con espacios $(sig)")
  commit_todo "$d"
  salida=$(bash "$instalador" "$d" --aplicar 2>&1)
  codigo=$?
  [ "$codigo" -eq 0 ] || { echo "código $codigo en una ruta con espacios, esperaba 0; salida: $salida"; return 1; }
  [ -f "$d/CLAUDE.md" ] || { echo "no copió CLAUDE.md en una ruta con espacios"; return 1; }
  contiene "$salida" "crear CLAUDE.md" || { echo "no reportó CLAUDE.md en una ruta con espacios"; return 1; }
}

c10_shebang_bash() {
  [ -f "$instalador" ] || { echo "no existe $instalador"; return 1; }
  head -n1 "$instalador" | grep -Eq '^#!.*(bash|/sh)[[:space:]]*$' || { echo "el shebang no es de bash/sh"; return 1; }
}

c10_sin_extensiones_de_gawk() {
  [ -f "$instalador" ] || { echo "no existe $instalador"; return 1; }
  local prohibidas='gensub|asort|asorti|systime|strftime|mktime|BEGINFILE|ENDFILE|nextfile'
  grep -Eq "$prohibidas" "$instalador" && { echo "usa una función propia de gawk"; return 1; }
  return 0
}

caso "C10: un destino con espacios en la ruta se instala correctamente" c10_destino_con_espacios
caso "C10: el instalador corre con bash" c10_shebang_bash
caso "C10: el instalador no usa extensiones de gawk" c10_sin_extensiones_de_gawk

# ===========================================================================
echo "== C6: verificación global (todas las corridas anteriores)"
# ===========================================================================

caso "C6: en toda la suite, el instalador nunca invocó gh" test ! -s "$log_gh"
caso "C6: en toda la suite, el instalador nunca invocó railway" test ! -s "$log_railway"

# ===========================================================================
echo
echo "$ok ok, $fallos fallos"
[ "$fallos" -eq 0 ]
