#!/usr/bin/env bash
# Pruebas de aceptación del instalador (T3b y subtarea B): instalador/instalar.sh copia el framework
# a otro repo sin pisar archivos, genera `.railway/railway.ts` y `.claude/identidad-agente.txt`,
# no crea ramas locales e imprime los pasos manuales. Ver .pipeline/criterios-T3b.md (C1 a C10) y
# .pipeline/criterios-B.md (B1 a B6, B8). Las secciones "B1" a "B6" llevan las pruebas nuevas de B;
# C4, C6 y C7 se reescribieron para el comportamiento nuevo.
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
org_marco=$(conf org)
# URL de un repo de la organización (B3, B6).
url_org="https://github.com/$org_marco/app.git"

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

# nuevo_repo <nombre> [--sin-origen] [--rama NOMBRE] [--origin URL]: crea un repo git en un
# directorio temporal (el nombre puede tener espacios, C10) con origin https://github.com/acme/demo.git,
# salvo que se pida otro con --origin o --sin-origen. Imprime la ruta por stdout. Ojo: se llama dentro
# de $(...), así que el contador de sig() no avanza; cada llamada necesita un <nombre> único.
nuevo_repo() {
  local nombre=$1
  shift
  local rama=main sin_origen=0 origin=https://github.com/acme/demo.git
  while [ $# -gt 0 ]; do
    case "$1" in
      --sin-origen) sin_origen=1; shift ;;
      --rama) rama=$2; shift 2 ;;
      --origin) origin=$2; shift 2 ;;
      *) shift ;;
    esac
  done
  local ruta="$tmp/repos/$(sig)-$nombre"
  mkdir -p "$ruta"
  git -C "$ruta" init -q -b "$rama"
  if [ "$sin_origen" -eq 0 ]; then
    git -C "$ruta" remote add origin "$origin"
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

# ejecutar_con <instalar.sh> <args...>: corre ese instalador y deja SALIDA, ERRSAL y CODIGO.
ejecutar_con() {
  local inst=$1 ef
  shift
  ef=$(mktemp "$tmp/stderr.XXXXXX")
  SALIDA=$(bash "$inst" "$@" 2>"$ef")
  CODIGO=$?
  ERRSAL=$(cat "$ef" 2>/dev/null)
  rm -f "$ef"
}

# ejecutar <args...>: corre el instalador real y deja SALIDA, ERRSAL y CODIGO.
ejecutar() {
  ejecutar_con "$instalador" "$@"
}

# fuente_falsa <nombre único> [clave=valor]...: copia de instalador/ con un manifiesto mínimo (uno.txt)
# y un pipeline.conf con esas claves cambiadas. Imprime la ruta de la fuente. Sirve para comprobar que
# el instalador lee bot, org y dueno de pipeline.conf y no los fija a mano.
fuente_falsa() {
  local f="$tmp/fuentes/$1" par
  shift
  mkdir -p "$f/.claude" "$f/instalador"
  cp -r "$repo/instalador/." "$f/instalador/"
  cp "$repo/.claude/pipeline.conf" "$f/.claude/pipeline.conf"
  for par in "$@"; do
    sed -i "s/^${par%%=*}=.*/${par%%=*}=${par#*=}/" "$f/.claude/pipeline.conf"
  done
  escribir "$f/uno.txt" "contenido uno"
  printf '%s\n' '# manifiesto de prueba' 'uno.txt' > "$f/instalador/manifiesto.txt"
  printf '%s' "$f"
}

# refs <ruta>: todas las referencias del repo con su objeto (ramas locales, remotas y etiquetas).
refs() {
  git -C "$1" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null
}

# pasos <salida>: lo que sigue a la línea "== Pasos manuales", incluida ella.
pasos() {
  printf '%s\n' "$1" | sed -n '/^== Pasos manuales/,$p'
}

# Los helpers que buscan no usan grep -q: con pipefail, un grep -q que cierra la tubería antes de
# tiempo hace fallar a printf (SIGPIPE) y da un falso "no está".

# linea_de <texto> <regex>: número de la primera línea que cumple la expresión (sin distinguir
# mayúsculas); vacío si ninguna.
linea_de() {
  printf '%s\n' "$1" | grep -inE -- "$2" | head -n1 | cut -d: -f1
}

# hay_linea <texto> <regex>: 0 si alguna línea cumple la expresión (grep -E).
hay_linea() {
  printf '%s\n' "$1" | grep -E -- "$2" > /dev/null
}

# hay_linea_i: como hay_linea, sin distinguir mayúsculas.
hay_linea_i() {
  printf '%s\n' "$1" | grep -iE -- "$2" > /dev/null
}

# linea_exacta <texto> <línea>: 0 si el texto tiene esa línea completa, igual (sin CR).
linea_exacta() {
  printf '%s\n' "$1" | tr -d '\r' | grep -Fx -- "$2" > /dev/null
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
  return 0
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

# B8 (C4 reescrito): la lista de generados incluye .claude/identidad-agente.txt.
c4_lista_de_generados() {
  local d salida f
  d=$(nuevo_repo c4-lista-nuevo --origin "$url_org")
  commit_todo "$d"
  ejecutar "$d"
  for f in .pipeline/lecciones-pendientes.md .pipeline/plan.json .railway/railway.ts .claude/identidad-agente.txt; do
    linea_exacta "$SALIDA" "crear $f" || { echo "modo nuevo: falta la línea 'crear $f'"; return 1; }
  done
  hay_linea "$SALIDA" '^(crear|igual|conflicto) \.pipeline/criterios-T1\.md$' \
    && { echo "modo nuevo: no debería listar criterios-T1.md"; return 1; }

  d=$(nuevo_repo c4-lista-existente --origin "$url_org")
  escribir "$d/src/app.py" "print(1)"
  commit_todo "$d"
  ejecutar "$d" --aplicar
  for f in .pipeline/lecciones-pendientes.md .pipeline/plan.json .pipeline/criterios-T1.md .railway/railway.ts .claude/identidad-agente.txt; do
    linea_exacta "$SALIDA" "crear $f" || { echo "modo existente: falta la línea 'crear $f'"; return 1; }
    [ -f "$d/$f" ] || { echo "modo existente: no escribió $f"; return 1; }
  done
}

caso "C4/B8: la lista de generados incluye .claude/identidad-agente.txt (y criterios-T1.md solo en modo existente)" c4_lista_de_generados

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
echo "== C6: rama staging (el instalador ya no la crea; ver B2)"
# ===========================================================================

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

caso "C6: si staging ya existe, no se mueve" c6_existente_no_se_toca
caso "C6: nunca hace push ni fetch (las referencias del remoto no cambian)" c6_no_toca_el_remoto
caso "C6: nunca agrega commits a la rama activa" c6_no_agrega_commits

# ===========================================================================
echo "== C7: pasos manuales (servicio y puerto; el resto de los pasos está en B5)"
# ===========================================================================

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
  return 0
}

c7_puerto_por_defecto() {
  local d salida
  d=$(nuevo_repo c7-defecto)
  commit_todo "$d"
  salida=$(bash "$instalador" "$d" --aplicar 2>&1)
  contiene "$salida" "PORT=8080" || { echo "el puerto por defecto no es 8080"; return 1; }
}

caso "C7: --servicio y --puerto se reemplazan en los pasos de Railway" c7_servicio_y_puerto_reemplazados
caso "C7: el puerto por defecto es 8080" c7_puerto_por_defecto

# ===========================================================================
echo "== B1: identidad del agente"
# ===========================================================================

b1_crea_con_una_linea_el_bot() {
  local d f
  d=$(nuevo_repo b1-crear --origin "$url_org")
  commit_todo "$d"
  f="$d/.claude/identidad-agente.txt"
  [ -n "$bot_marco" ] || { echo "pipeline.conf no define bot"; return 1; }
  ejecutar "$d"
  [ "$CODIGO" -eq 0 ] || { echo "código $CODIGO, esperaba 0"; return 1; }
  linea_exacta "$SALIDA" "crear .claude/identidad-agente.txt" || { echo "simulación: falta la línea 'crear .claude/identidad-agente.txt'"; return 1; }
  [ -e "$f" ] && { echo "la simulación escribió identidad-agente.txt"; return 1; }
  ejecutar "$d" --aplicar
  [ "$CODIGO" -eq 0 ] || { echo "--aplicar: código $CODIGO, esperaba 0"; return 1; }
  [ -f "$f" ] || { echo "--aplicar no generó $f"; return 1; }
  [ "$(grep -c '' "$f")" -eq 1 ] || { echo "no tiene exactamente una línea ($(grep -c '' "$f"))"; return 1; }
  [ "$(tr -d '\r\n' < "$f")" = "$bot_marco" ] || { echo "el contenido no es el bot de pipeline.conf ($bot_marco): $(cat "$f")"; return 1; }
}

b1_el_bot_sale_de_pipeline_conf() {
  local fuente d f
  fuente=$(fuente_falsa b1-bot-otro bot=otro-bot-x)
  d=$(nuevo_repo b1-bot-otro --origin "$url_org")
  commit_todo "$d"
  ejecutar_con "$fuente/instalador/instalar.sh" "$d" --aplicar
  [ "$CODIGO" -eq 0 ] || { echo "código $CODIGO, esperaba 0; salida: $SALIDA"; return 1; }
  f="$d/.claude/identidad-agente.txt"
  [ -f "$f" ] || { echo "no generó $f"; return 1; }
  [ "$(tr -d '\r\n' < "$f")" = "otro-bot-x" ] || { echo "no usó bot= del pipeline.conf de la fuente: $(cat "$f")"; return 1; }
}

b1_segunda_corrida_igual() {
  local d f antes despues
  d=$(nuevo_repo b1-igual --origin "$url_org")
  commit_todo "$d"
  ejecutar "$d" --aplicar
  f="$d/.claude/identidad-agente.txt"
  [ -f "$f" ] || { echo "no generó $f en la primera corrida"; return 1; }
  antes=$(cat "$f")
  ejecutar "$d" --aplicar
  [ "$CODIGO" -eq 0 ] || { echo "segunda corrida: código $CODIGO, esperaba 0"; return 1; }
  linea_exacta "$SALIDA" "igual .claude/identidad-agente.txt" || { echo "no marcó identidad-agente.txt como igual"; return 1; }
  despues=$(cat "$f")
  [ "$antes" = "$despues" ] || { echo "la segunda corrida cambió el archivo"; return 1; }
}

b1_preexistente_con_ese_contenido_es_igual() {
  local a b
  a=$(nuevo_repo b1-igual-base --origin "$url_org")
  commit_todo "$a"
  ejecutar "$a" --aplicar
  [ -f "$a/.claude/identidad-agente.txt" ] || { echo "no generó el archivo base"; return 1; }
  b=$(nuevo_repo b1-igual-copia --origin "$url_org")
  mkdir -p "$b/.claude"
  cp "$a/.claude/identidad-agente.txt" "$b/.claude/identidad-agente.txt"
  commit_todo "$b"
  ejecutar "$b"
  [ "$CODIGO" -eq 0 ] || { echo "código $CODIGO, esperaba 0"; return 1; }
  linea_exacta "$SALIDA" "igual .claude/identidad-agente.txt" || { echo "un archivo con el contenido generado debería ser 'igual'"; return 1; }
}

# b1_conflicto_con <nombre único> <contenido> [--aplicar]: un archivo con otro contenido es conflicto y
# no se pisa.
b1_conflicto_con() {
  local nombre=$1 contenido=$2 d f snap
  shift 2
  d=$(nuevo_repo "b1-conflicto-$nombre" --origin "$url_org")
  escribir "$d/.claude/identidad-agente.txt" "$contenido"
  commit_todo "$d"
  f="$d/.claude/identidad-agente.txt"
  snap="$tmp/identidad-conflicto-$nombre"
  cp "$f" "$snap"
  ejecutar "$d" "$@"
  [ "$CODIGO" -eq 3 ] || { echo "código $CODIGO, esperaba 3"; return 1; }
  linea_exacta "$SALIDA" "conflicto .claude/identidad-agente.txt" || { echo "no reportó el conflicto"; return 1; }
  cmp -s "$snap" "$f" || { echo "pisó el archivo en conflicto"; return 1; }
  hay_linea "$(pasos "$SALIDA")" '^diff .*identidad-agente\.txt' || { echo "el bloque de conflictos no trae un diff de identidad-agente.txt"; return 1; }
}

b1_no_cuenta_para_el_modo() {
  local d
  d=$(nuevo_repo b1-modo-nuevo --origin "$url_org")
  escribir "$d/README.md" "hola"
  escribir "$d/.claude/identidad-agente.txt" "$bot_marco
"
  commit_todo "$d"
  ejecutar "$d"
  linea_exacta "$SALIDA" "modo nuevo" || { echo "README + identidad-agente.txt debería seguir en 'modo nuevo'"; return 1; }
  ! linea_exacta "$SALIDA" "modo existente" || { echo "dijo 'modo existente'"; return 1; }

  # Contraste: con otro archivo de verdad sí es existente.
  d=$(nuevo_repo b1-modo-existente --origin "$url_org")
  escribir "$d/src/app.py" "print(1)"
  escribir "$d/.claude/identidad-agente.txt" "$bot_marco
"
  commit_todo "$d"
  ejecutar "$d"
  linea_exacta "$SALIDA" "modo existente" || { echo "con src/app.py debería ser 'modo existente'"; return 1; }
}

b1_manifiesto_no_lo_lista() {
  [ -f "$manifiesto" ] || { echo "no existe $manifiesto"; return 1; }
  if tr -d '\r' < "$manifiesto" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -Fx ".claude/identidad-agente.txt" > /dev/null; then
    echo "el manifiesto lista .claude/identidad-agente.txt"
    return 1
  fi
}

caso "B1: crea .claude/identidad-agente.txt con una sola línea, el bot de pipeline.conf (y la simulación no escribe)" b1_crea_con_una_linea_el_bot
caso "B1: el bot sale de pipeline.conf de la fuente, no está fijo" b1_el_bot_sale_de_pipeline_conf
caso "B1: en una segunda corrida el archivo cuenta como igual y no cambia" b1_segunda_corrida_igual
caso "B1: un archivo preexistente con ese contenido es igual" b1_preexistente_con_ese_contenido_es_igual
caso "B1: con otro contenido es conflicto, sale 3 y no se pisa (simulación)" b1_conflicto_con sim "otro-bot
"
caso "B1: con otro contenido es conflicto, sale 3 y no se pisa (--aplicar)" b1_conflicto_con apl "otro-bot
" --aplicar
caso "B1: el bot con una segunda línea es conflicto" b1_conflicto_con dos-lineas "$bot_marco
segunda
" --aplicar
caso "B1: un archivo vacío es conflicto" b1_conflicto_con vacio "" --aplicar
caso "B1: no cuenta para detectar el modo (README + identidad = nuevo; con src/app.py = existente)" b1_no_cuenta_para_el_modo
caso "B1: el manifiesto no lista .claude/identidad-agente.txt" b1_manifiesto_no_lo_lista

# ===========================================================================
echo "== B2: staging no se crea en local"
# ===========================================================================

# b2_no_crea <sim|apl> <con|sin>: sin staging previo, no toca ninguna referencia y dice "no se crea".
b2_no_crea() {
  local modo=$1 commits=$2 d antes despues activa args=()
  d=$(nuevo_repo "b2-no-crea-$modo-$commits" --rama trabajo --origin "$url_org")
  [ "$commits" = con ] && commit_todo "$d"
  [ "$modo" = apl ] && args=(--aplicar)
  antes=$(refs "$d")
  activa=$(git -C "$d" branch --show-current)
  ejecutar "$d" ${args[@]+"${args[@]}"}
  [ "$CODIGO" -eq 0 ] || { echo "código $CODIGO, esperaba 0"; return 1; }
  [ "$(printf '%s\n' "$SALIDA" | grep '^rama staging:')" = "rama staging: no se crea" ] \
    || { echo "esperaba exactamente 'rama staging: no se crea', salió: $(printf '%s\n' "$SALIDA" | grep '^rama staging:')"; return 1; }
  despues=$(refs "$d")
  [ "$antes" = "$despues" ] || { echo "cambiaron las referencias del repo"; return 1; }
  git -C "$d" show-ref --verify --quiet refs/heads/staging && { echo "creó la rama staging"; return 1; }
  [ "$(git -C "$d" branch --show-current)" = "$activa" ] || { echo "cambió la rama activa"; return 1; }
  return 0
}

# b2_existe_local <sim|apl>: con staging local dicen "existe" y no se mueve.
b2_existe_local() {
  local modo=$1 d viejo args=() antes
  d=$(nuevo_repo "b2-existe-$modo" --origin "$url_org")
  commit_todo "$d" primero
  viejo=$(git -C "$d" rev-parse HEAD)
  git -C "$d" branch staging "$viejo"
  commit_todo "$d" segundo
  [ "$modo" = apl ] && args=(--aplicar)
  antes=$(refs "$d")
  ejecutar "$d" ${args[@]+"${args[@]}"}
  [ "$(printf '%s\n' "$SALIDA" | grep '^rama staging:')" = "rama staging: existe" ] \
    || { echo "esperaba exactamente 'rama staging: existe', salió: $(printf '%s\n' "$SALIDA" | grep '^rama staging:')"; return 1; }
  [ "$(git -C "$d" rev-parse staging)" = "$viejo" ] || { echo "movió staging"; return 1; }
  [ "$antes" = "$(refs "$d")" ] || { echo "cambiaron las referencias del repo"; return 1; }
}

b2_existe_si_es_la_rama_activa() {
  local d
  d=$(nuevo_repo b2-existe-activa --rama staging --origin "$url_org")
  commit_todo "$d"
  ejecutar "$d" --aplicar
  linea_exacta "$SALIDA" "rama staging: existe" || { echo "con staging como rama activa esperaba 'rama staging: existe'"; return 1; }
}

# b2_solo_origin_staging <sim|apl>: staging solo como origin/staging.
b2_solo_origin_staging() {
  local modo=$1 d args=() antes
  d=$(nuevo_repo "b2-origin-staging-$modo" --origin "$url_org")
  commit_todo "$d"
  git -C "$d" update-ref refs/remotes/origin/staging HEAD
  [ "$modo" = apl ] && args=(--aplicar)
  antes=$(refs "$d")
  ejecutar "$d" ${args[@]+"${args[@]}"}
  linea_exacta "$SALIDA" "rama staging: existe" || { echo "con origin/staging esperaba 'rama staging: existe'"; return 1; }
  hay_linea "$SALIDA" '^nota: staging existe solo como origin/staging' || { echo "falta la nota 'staging existe solo como origin/staging'"; return 1; }
  git -C "$d" show-ref --verify --quiet refs/heads/staging && { echo "creó la rama local staging"; return 1; }
  [ "$antes" = "$(refs "$d")" ] || { echo "cambiaron las referencias del repo"; return 1; }
}

# Contraste: otra rama remota (origin/main) no cuenta como staging.
b2_otra_rama_remota_no_es_staging() {
  local d
  d=$(nuevo_repo b2-origin-main --origin "$url_org")
  commit_todo "$d"
  git -C "$d" update-ref refs/remotes/origin/main HEAD
  ejecutar "$d" --aplicar
  linea_exacta "$SALIDA" "rama staging: no se crea" || { echo "con solo origin/main esperaba 'rama staging: no se crea'"; return 1; }
}

# Un staging que existe en el remoto pero que no se trajo no se ve: el instalador no hace fetch.
b2_no_hace_fetch() {
  local bare d antes_local antes_remoto
  bare="$tmp/remotos/b2-fetch.git"
  git init -q --bare "$bare"
  d=$(nuevo_repo b2-fetch --sin-origen)
  git -C "$d" remote add origin "$bare"
  commit_todo "$d"
  git -C "$d" push -q origin main:main main:staging
  git -C "$d" update-ref -d refs/remotes/origin/staging
  antes_local=$(refs "$d")
  antes_remoto=$(git -C "$bare" show-ref)
  ejecutar "$d" --aplicar
  [ "$antes_remoto" = "$(git -C "$bare" show-ref)" ] || { echo "cambió el remoto"; return 1; }
  [ "$antes_local" = "$(refs "$d")" ] || { echo "cambiaron las referencias locales (¿hizo fetch?)"; return 1; }
  linea_exacta "$SALIDA" "rama staging: no se crea" || { echo "sin origin/staging local esperaba 'rama staging: no se crea'"; return 1; }
}

caso "B2: con commits y sin staging, la simulación dice 'no se crea' y no toca ninguna referencia" b2_no_crea sim con
caso "B2: con commits y sin staging, --aplicar dice 'no se crea' y no crea ni mueve ramas" b2_no_crea apl con
caso "B2: sin commits, la simulación dice 'no se crea' (ya no 'sin commits')" b2_no_crea sim sin
caso "B2: sin commits, --aplicar dice 'no se crea' (ya no 'sin commits')" b2_no_crea apl sin
caso "B2: con staging local dice 'existe' y no lo mueve (simulación)" b2_existe_local sim
caso "B2: con staging local dice 'existe' y no lo mueve (--aplicar)" b2_existe_local apl
caso "B2: si staging es la rama activa dice 'existe'" b2_existe_si_es_la_rama_activa
caso "B2: con solo origin/staging dice 'existe', trae su nota y no crea la rama (simulación)" b2_solo_origin_staging sim
caso "B2: con solo origin/staging dice 'existe', trae su nota y no crea la rama (--aplicar)" b2_solo_origin_staging apl
caso "B2: otra rama remota (origin/main) no cuenta como staging" b2_otra_rama_remota_no_es_staging
caso "B2: no hace fetch: un staging solo del remoto, sin traer, no se ve y el remoto no cambia" b2_no_hace_fetch

# ===========================================================================
echo "== B3: repo de la organización, sin notas"
# ===========================================================================

# b3_sin_notas <nombre único> <url> <con|sin> [--aplicar]
b3_sin_notas() {
  local nombre=$1 url=$2 commits=$3 d
  shift 3
  d=$(nuevo_repo "b3-$nombre" --origin "$url")
  [ "$commits" = con ] && commit_todo "$d"
  ejecutar "$d" "$@"
  [ "$CODIGO" -eq 0 ] || { echo "código $CODIGO, esperaba 0"; return 1; }
  if hay_linea "$SALIDA" '^nota:'; then
    echo "salieron notas: $(printf '%s\n' "$SALIDA" | grep '^nota:')"
    return 1
  fi
  ! contiene "$SALIDA" "el dueño del repo" || { echo "salió la nota del dueño"; return 1; }
}

b3_org_sale_de_pipeline_conf() {
  local fuente d
  # org=acme en la fuente: un repo de acme no lleva notas, aunque su dueño no sea el de dueno=.
  fuente=$(fuente_falsa b3-org-acme org=acme)
  d=$(nuevo_repo b3-org-acme)
  commit_todo "$d"
  ejecutar_con "$fuente/instalador/instalar.sh" "$d"
  if hay_linea "$SALIDA" '^nota:'; then
    echo "con org=acme, un repo de acme no debería traer notas: $(printf '%s\n' "$SALIDA" | grep '^nota:')"
    return 1
  fi
  # Contraste: con esa misma fuente, un repo de la organización real sí es ajeno.
  d=$(nuevo_repo b3-org-acme-ajeno --origin "$url_org")
  commit_todo "$d"
  ejecutar_con "$fuente/instalador/instalar.sh" "$d"
  hay_linea "$SALIDA" '^nota: el destino no es un repo de acme' \
    || { echo "con org=acme, un repo de $org_marco debería traer 'nota: el destino no es un repo de acme'"; return 1; }
}

caso "B3: repo de la organización con commits, sin staging: ninguna nota" b3_sin_notas con-sim "$url_org" con
caso "B3: repo de la organización sin commits: ninguna nota" b3_sin_notas sin-sim "$url_org" sin
caso "B3: repo de la organización con commits y --aplicar: ninguna nota" b3_sin_notas con-apl "$url_org" con --aplicar
caso "B3: repo de la organización sin commits y --aplicar: ninguna nota" b3_sin_notas sin-apl "$url_org" sin --aplicar
caso "B3: origin sin .git: ninguna nota" b3_sin_notas sin-punto-git "https://github.com/$org_marco/app" con
caso "B3: origin ssh git@github.com:<org>/<repo>.git: ninguna nota" b3_sin_notas ssh "git@github.com:$org_marco/app.git" con
caso "B3: la organización se compara sin distinguir mayúsculas" b3_sin_notas mayusculas "https://github.com/${org_marco^^}/app.git" con
caso "B3/B4: la organización sale de org= en pipeline.conf, no está fija" b3_org_sale_de_pipeline_conf

# ===========================================================================
echo "== B4: fuera de la organización"
# ===========================================================================

# b4_nota_destino <nombre único> <url | SIN>: sale la nota de que el destino no es de la organización.
b4_nota_destino() {
  local nombre=$1 url=$2 d
  if [ "$url" = SIN ]; then
    d=$(nuevo_repo "b4-$nombre" --sin-origen)
  else
    d=$(nuevo_repo "b4-$nombre" --origin "$url")
  fi
  commit_todo "$d"
  ejecutar "$d"
  hay_linea "$SALIDA" "^nota: el destino no es un repo de $org_marco" \
    || { echo "falta 'nota: el destino no es un repo de $org_marco'; notas: $(printf '%s\n' "$SALIDA" | grep '^nota:')"; return 1; }
}

b4_notas_de_hoy() {
  local d
  d=$(nuevo_repo b4-hoy-sin-origin --sin-origen)
  commit_todo "$d"
  ejecutar "$d"
  hay_linea "$SALIDA" '^nota: sin origin: el repo sale del nombre de la carpeta' || { echo "sin origin: falta la nota 'sin origin'"; return 1; }

  d=$(nuevo_repo b4-hoy-no-github --origin "https://gitlab.com/$org_marco/app.git")
  commit_todo "$d"
  ejecutar "$d"
  hay_linea "$SALIDA" '^nota: origin no apunta a un repo de github.com' || { echo "origin que no es de GitHub: falta la nota"; return 1; }

  d=$(nuevo_repo b4-hoy-dueno)
  commit_todo "$d"
  ejecutar "$d"
  hay_linea "$SALIDA" "^nota: el dueño del repo \(acme\) no es el de \.claude/pipeline\.conf \($dueno_marco\)" \
    || { echo "dueño distinto: falta la nota del dueño"; return 1; }
}

# Contraste: si el dueño del origin es el de dueno= (pero no es la organización), sale la nota del
# destino y no la del dueño.
b4_dueno_igual_no_lleva_nota_de_dueno() {
  local d
  d=$(nuevo_repo b4-dueno-igual --origin "https://github.com/$dueno_marco/app.git")
  commit_todo "$d"
  ejecutar "$d"
  hay_linea "$SALIDA" "^nota: el destino no es un repo de $org_marco" || { echo "falta la nota del destino"; return 1; }
  ! contiene "$SALIDA" "el dueño del repo" || { echo "salió la nota del dueño con dueño igual al de dueno="; return 1; }
}

caso "B4: origin de otro dueño (https://github.com/o/r.git): nota 'el destino no es un repo de <org>'" b4_nota_destino otro-dueno "https://github.com/o/r.git"
caso "B4: sin origin: nota 'el destino no es un repo de <org>'" b4_nota_destino sin-origin SIN
caso "B4: origin que no es de GitHub: nota 'el destino no es un repo de <org>'" b4_nota_destino no-github "https://gitlab.com/$org_marco/app.git"
caso "B4: una organización que solo empieza igual (<org>-otra) no cuenta" b4_nota_destino prefijo "https://github.com/$org_marco-otra/app.git"
caso "B4: la organización como nombre de repo de otro dueño no cuenta" b4_nota_destino como-repo "https://github.com/otra/$org_marco.git"
caso "B4: siguen saliendo las notas de hoy (sin origin, origin no GitHub, dueño distinto)" b4_notas_de_hoy
caso "B4: con dueño igual al de dueno= no sale la nota del dueño" b4_dueno_igual_no_lleva_nota_de_dueno

# ===========================================================================
echo "== B5: pasos manuales"
# ===========================================================================

b5_encabezado() {
  local d p enc
  d=$(nuevo_repo b5-encabezado --origin "$url_org")
  commit_todo "$d"
  ejecutar "$d"
  p=$(pasos "$SALIDA")
  enc=$(printf '%s\n' "$p" | sed -n '2,$p' | grep -m1 '[^[:space:]]')
  [ -n "$enc" ] || { echo "no hay nada después de '== Pasos manuales'"; return 1; }
  contiene "$enc" "/crear-repo" || { echo "la primera línea no nombra /crear-repo: $enc"; return 1; }
  contiene "$enc" "T0" || { echo "la primera línea no nombra el PR T0: $enc"; return 1; }
  contiene "$enc" "staging" || { echo "la primera línea no nombra staging: $enc"; return 1; }
  hay_linea_i "$enc" 'ruleset' || { echo "la primera línea no nombra los rulesets de la organización: $enc"; return 1; }
}

b5_orden_sin_conflictos() {
  local d p enc cp gcd rein ident rw radd v
  d=$(nuevo_repo b5-orden --origin "$url_org")
  commit_todo "$d"
  ejecutar "$d"
  [ "$CODIGO" -eq 0 ] || { echo "código $CODIGO, esperaba 0"; return 1; }
  p=$(pasos "$SALIDA")
  enc=$(linea_de "$p" '/crear-repo')
  cp=$(linea_de "$p" 'cp \.claude/settings\.local\.example\.json \.claude/settings\.local\.json')
  gcd=$(linea_de "$p" 'GH_CONFIG_DIR')
  rein=$(linea_de "$p" 'reinici')
  ident=$(linea_de "$p" 'identidad-agente\.txt')
  rw=$(linea_de "$p" 'cuando staging ya exista')
  radd=$(linea_de "$p" 'railway add')
  for v in enc cp gcd rein ident rw radd; do
    [ -n "${!v}" ] || { echo "no encontré en los pasos: $v"; return 1; }
  done
  [ "$enc" -lt "$cp" ] && [ "$cp" -le "$gcd" ] && [ "$gcd" -le "$rein" ] && [ "$rein" -le "$ident" ] \
    && [ "$ident" -lt "$rw" ] && [ "$rw" -le "$radd" ] \
    || { echo "orden equivocado (línea de cada uno): encabezado=$enc cp=$cp GH_CONFIG_DIR=$gcd reiniciar=$rein identidad=$ident 'cuando staging ya exista'=$rw railway_add=$radd"; return 1; }
  hay_linea "$p" '^diff ' && { echo "sin conflictos no debería salir ningún diff"; return 1; }
  contiene "$SALIDA" "onflicto" && { echo "sin conflictos no debería aparecer la palabra conflicto"; return 1; }
  return 0
}

b5_orden_con_conflictos() {
  local d p enc cf dif cp v
  d=$(nuevo_repo b5-orden-conflicto --origin "$url_org")
  cp "$repo/.gitattributes" "$d/.gitattributes"
  printf 'x' >> "$d/.gitattributes"
  commit_todo "$d"
  ejecutar "$d"
  [ "$CODIGO" -eq 3 ] || { echo "código $CODIGO, esperaba 3"; return 1; }
  p=$(pasos "$SALIDA")
  enc=$(linea_de "$p" '/crear-repo')
  cf=$(linea_de "$p" 'conflictos')
  dif=$(linea_de "$p" '^diff .*\.gitattributes')
  cp=$(linea_de "$p" 'cp \.claude/settings\.local\.example\.json \.claude/settings\.local\.json')
  for v in enc cf dif cp; do
    [ -n "${!v}" ] || { echo "no encontré en los pasos: $v"; return 1; }
  done
  [ "$enc" -lt "$cf" ] && [ "$cf" -le "$dif" ] && [ "$dif" -lt "$cp" ] \
    || { echo "el bloque de conflictos debe ir entre el encabezado y la sección Agente: encabezado=$enc conflictos=$cf diff=$dif cp=$cp"; return 1; }
}

b5_agente() {
  local d p linea_ident
  d=$(nuevo_repo b5-agente --origin "$url_org")
  commit_todo "$d"
  ejecutar "$d"
  p=$(pasos "$SALIDA")
  linea_exacta "$p" '[ -e .claude/settings.local.json ] || cp .claude/settings.local.example.json .claude/settings.local.json' \
    || { echo "falta la línea exacta del cp de settings.local.json"; return 1; }
  contiene "$p" "GH_CONFIG_DIR" || { echo "falta la indicación de completar GH_CONFIG_DIR"; return 1; }
  hay_linea_i "$p" 'reinici' || { echo "falta reiniciar la sesión"; return 1; }
  linea_ident=$(printf '%s\n' "$p" | grep -m1 'identidad-agente\.txt')
  [ -n "$linea_ident" ] || { echo "ninguna línea menciona .claude/identidad-agente.txt"; return 1; }
  hay_linea_i "$linea_ident" 'incluid' || { echo "la línea de identidad-agente.txt no dice que ya viene incluido: $linea_ident"; return 1; }
}

b5_no_pide_identidad_por_pr() {
  local d p l
  d=$(nuevo_repo b5-identidad-pr --origin "$url_org")
  commit_todo "$d"
  ejecutar "$d"
  p=$(pasos "$SALIDA")
  while IFS= read -r l; do
    hay_linea "$l" 'identidad-agente' || continue
    hay_linea "$l" '\bPR\b|gobierno|aprueba|mergea' && { echo "una línea sobre identidad-agente.txt pide un PR: $l"; return 1; }
  done <<< "$p"
  hay_linea "$p" 'PR de gobierno|lo apruebas y lo mergeas' && { echo "sigue el paso viejo del PR de gobierno de la identidad"; return 1; }
  return 0
}

b5_railway() {
  local d p rw r
  d=$(nuevo_repo b5-railway --origin "$url_org")
  commit_todo "$d"
  ejecutar "$d"
  p=$(pasos "$SALIDA")
  rw=$(linea_de "$p" 'cuando staging ya exista')
  [ -n "$rw" ] || { echo "la sección Railway no está marcada 'cuando staging ya exista'"; return 1; }
  r=$(printf '%s\n' "$p" | sed -n "${rw},\$p")
  contiene "$r" "railway init --name app" || { echo "falta 'railway init --name app'"; return 1; }
  contiene "$r" "railway add --service app --repo $org_marco/app --branch main" || { echo "falta 'railway add'"; return 1; }
  contiene "$r" "railway environment new staging --duplicate production --service-config app source.branch staging" \
    || { echo "falta 'railway environment new'"; return 1; }
  contiene "$r" "railway variable set PORT=8080 --service app --environment production --skip-deploys" \
    || { echo "falta la variable PORT en production"; return 1; }
  contiene "$r" "railway variable set PORT=8080 --service app --environment staging --skip-deploys" \
    || { echo "falta la variable PORT en staging"; return 1; }
  contiene "$r" "railway domain --port 8080 --service app --environment production" || { echo "falta 'railway domain' en production"; return 1; }
  contiene "$r" "railway domain --port 8080 --service app --environment staging" || { echo "falta 'railway domain' en staging"; return 1; }
  contiene "$r" "npm install --save-dev railway@3.11.0" || { echo "falta instalar el SDK railway@3.11.0"; return 1; }
  contiene "$r" "Node 22" || { echo "falta la nota de Node 22"; return 1; }
  contiene "$r" "railway environment link production" || { echo "falta 'environment link production'"; return 1; }
  contiene "$r" "railway environment link staging" || { echo "falta 'environment link staging'"; return 1; }
  contiene "$r" "railway config plan" || { echo "falta 'railway config plan'"; return 1; }
  contiene "$r" "railway config apply" || { echo "falta 'railway config apply'"; return 1; }
  hay_linea_i "$(printf '%s\n' "$r" | grep -i 'github app')" 'railway' || { echo "falta la línea que nombra la GitHub App de Railway"; return 1; }
  hay_linea "$(printf '%s\n' "$r" | grep -i 'github app')" 'All repositories' || { echo "la línea de la GitHub App no dice 'All repositories'"; return 1; }
}

b5_sin_placeholders() {
  local d p
  d=$(nuevo_repo b5-placeholders --origin "$url_org")
  commit_todo "$d"
  ejecutar "$d" --servicio miapi --puerto 3000
  p=$(pasos "$SALIDA")
  contiene "$p" "{{" && { echo "quedó un marcador {{...}} sin reemplazar"; return 1; }
  contiene "$p" "}}" && { echo "quedó un marcador {{...}} sin reemplazar (cierre)"; return 1; }
  contiene "$p" "<dueño>" && { echo "quedó <dueño> sin reemplazar"; return 1; }
  contiene "$p" "<repo>" && { echo "quedó <repo> sin reemplazar"; return 1; }
  contiene "$p" "<servicio>" && { echo "quedó <servicio> sin reemplazar"; return 1; }
  contiene "$p" "<puerto>" && { echo "quedó <puerto> sin reemplazar"; return 1; }
  contiene "$p" "railway add --service miapi --repo $org_marco/app --branch main" || { echo "no reemplazó servicio/dueño/repo"; return 1; }
  contiene "$p" "PORT=3000" || { echo "no reemplazó el puerto"; return 1; }
  return 0
}

# b5_ya_no_salen <variante>: en ninguna forma salen los pasos de git ni de GitHub de antes.
b5_ya_no_salen() {
  local v=$1 d pat
  case "$v" in
    main) d=$(nuevo_repo b5-no-main --origin "$url_org"); commit_todo "$d" ;;
    rama-trabajo) d=$(nuevo_repo b5-no-trabajo --rama trabajo --origin "$url_org"); commit_todo "$d" ;;
    staging-activa) d=$(nuevo_repo b5-no-staging-activa --rama staging --origin "$url_org"); commit_todo "$d" ;;
    sin-commits) d=$(nuevo_repo b5-no-sin-commits --origin "$url_org") ;;
    sin-origin) d=$(nuevo_repo b5-no-sin-origin --sin-origen); commit_todo "$d" ;;
    fuera-de-org) d=$(nuevo_repo b5-no-fuera); commit_todo "$d" ;;
    conflicto)
      d=$(nuevo_repo b5-no-conflicto --origin "$url_org")
      cp "$repo/.gitattributes" "$d/.gitattributes"
      printf 'x' >> "$d/.gitattributes"
      commit_todo "$d"
      ;;
  esac
  ejecutar "$d" --aplicar
  [ "$CODIGO" -eq 0 ] || [ "$CODIGO" -eq 3 ] || { echo "código $CODIGO"; return 1; }
  contiene "$SALIDA" "== Pasos manuales" || { echo "no imprimió los pasos manuales"; return 1; }
  for pat in 'git commit' 'git push' 'git switch staging' 'git merge --ff-only' 'merge --ff-only' \
    'repos/[^ ]*/collaborators' 'repository_invitations' 'branches/[^ ]*/protection'; do
    hay_linea "$SALIDA" "$pat" && { echo "todavía sale algo que cumple '$pat': $(printf '%s\n' "$SALIDA" | grep -E -m1 -- "$pat")"; return 1; }
  done
  return 0
}

b5_sin_tokens() {
  local d pat
  d=$(nuevo_repo b5-tokens --origin "$url_org")
  commit_todo "$d"
  ejecutar "$d" --aplicar
  for pat in 'ghp_' 'github_pat_' 'gho_' 'GH_TOKEN' 'GITHUB_TOKEN' 'gh auth token' 'show-token' 'auth status -t'; do
    hay_linea "$SALIDA" "$pat" && { echo "imprime o pide un token ($pat)"; return 1; }
  done
  return 0
}

caso "B5: la primera línea de los pasos dice que /crear-repo hace el git, el PR T0 y staging, y que la protección son los rulesets" b5_encabezado
caso "B5: orden encabezado, Agente y Railway ('cuando staging ya exista'), sin diff ni 'conflicto' si no hay conflictos" b5_orden_sin_conflictos
caso "B5: con conflictos, el bloque de conflictos (con su diff) va entre el encabezado y la sección Agente" b5_orden_con_conflictos
caso "B5: la sección Agente trae el cp exacto, GH_CONFIG_DIR, reiniciar la sesión y la identidad ya incluida" b5_agente
caso "B5: ninguna línea pide crear .claude/identidad-agente.txt por PR" b5_no_pide_identidad_por_pr
caso "B5: la sección Railway trae los comandos de hoy reemplazados, la GitHub App con All repositories y railway@3.11.0" b5_railway
caso "B5: sin marcadores {{...}} ni <dueño>/<repo>/<servicio>/<puerto>; --servicio y --puerto reemplazados" b5_sin_placeholders
caso "B5: no salen los pasos de git/GitHub de antes (repo en main)" b5_ya_no_salen main
caso "B5: no salen los pasos de git/GitHub de antes (rama activa trabajo)" b5_ya_no_salen rama-trabajo
caso "B5: no salen los pasos de git/GitHub de antes (rama activa staging)" b5_ya_no_salen staging-activa
caso "B5: no salen los pasos de git/GitHub de antes (sin commits)" b5_ya_no_salen sin-commits
caso "B5: no salen los pasos de git/GitHub de antes (sin origin)" b5_ya_no_salen sin-origin
caso "B5: no salen los pasos de git/GitHub de antes (repo fuera de la organización)" b5_ya_no_salen fuera-de-org
caso "B5: no salen los pasos de git/GitHub de antes (con conflicto)" b5_ya_no_salen conflicto
caso "B5: ningún comando impreso contiene un token ni pide imprimirlo" b5_sin_tokens

# ===========================================================================
echo "== B6: contrato con el paso 0 de /crear-repo"
# ===========================================================================

b6_contrato_paso_0() {
  local d antes despues
  d=$(nuevo_repo b6-contrato --origin "https://github.com/$org_marco/app.git")
  commit_todo "$d"
  antes=$(huella "$d")
  ejecutar "$d"
  [ "$CODIGO" -eq 0 ] || { echo "código $CODIGO, esperaba 0"; return 1; }
  linea_exacta "$SALIDA" "crear .claude/identidad-agente.txt" || { echo "falta la línea exacta 'crear .claude/identidad-agente.txt'"; return 1; }
  ! linea_exacta "$SALIDA" "rama staging: crear" || { echo "sigue saliendo 'rama staging: crear'"; return 1; }
  if hay_linea "$SALIDA" '^nota:'; then
    echo "salieron notas: $(printf '%s\n' "$SALIDA" | grep '^nota:')"
    return 1
  fi
  despues=$(huella "$d")
  [ "$antes" = "$despues" ] || { echo "la simulación cambió el destino"; return 1; }
}

caso "B6: repo de la organización con un commit vacío: 'crear .claude/identidad-agente.txt', sin 'rama staging: crear' y sin notas" b6_contrato_paso_0

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
  return 0
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
