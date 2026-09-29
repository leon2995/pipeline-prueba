#!/usr/bin/env bash
# Pruebas unitarias del instalador (T3b): las funciones de instalador/instalar.sh (se cargan con
# source, sin correr main) y casos de borde de punta a punta que no cubren las pruebas de
# aceptación. Cada regla tiene casos que deben pasar y casos que deben fallar.
#
# Uso: bash tests/unit/test-instalar.sh
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
instalador="$repo/instalador/instalar.sh"
# shellcheck source=../../instalador/instalar.sh
. "$instalador"

ok=0
fallos=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------------------------
# utilidades
# ---------------------------------------------------------------------------

# caso <descripción> <función> [args...]: ok si la función sale 0; si no, FALLO con lo que imprimió.
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

# g <ruta> <args...>: git en esa carpeta. Con cd y no con git -C: en Git Bash, una ruta POSIX con
# comillas simples no llega convertida a git.exe.
g() {
  local d=$1
  shift
  (cd "$d" && git "$@")
}

# nuevo_repo <nombre> [rama]: repo git temporal (el nombre puede tener espacios y comillas) con
# origin https://github.com/acme/demo.git. Imprime la ruta.
nuevo_repo() {
  local base ruta
  base=$(mktemp -d "$tmp/repo.XXXXXX")
  ruta="$base/$1"
  mkdir -p "$ruta"
  g "$ruta" init -q -b "${2:-main}"
  g "$ruta" remote add origin https://github.com/acme/demo.git
  printf '%s' "$ruta"
}

commit_todo() {
  g "$1" add -A
  g "$1" -c user.name=x -c user.email=x@x.com commit -q -m "${2:-inicial}" --allow-empty
}

# huella <ruta>: hash de los archivos (menos .git), ramas locales y git status.
huella() {
  (
    cd "$1" || exit 1
    find . -path './.git' -prune -o -type f -print0 2> /dev/null | sort -z | xargs -0 sha1sum 2> /dev/null
    git for-each-ref --format='%(refname) %(objectname)' refs/heads 2> /dev/null
    git status --porcelain 2> /dev/null
  )
}

# correr <instalador> <args...>: deja SALIDA, ERRSAL y CODIGO.
correr() {
  local script=$1 ef
  shift
  ef=$(mktemp "$tmp/stderr.XXXXXX")
  SALIDA=$(bash "$script" "$@" 2> "$ef")
  CODIGO=$?
  ERRSAL=$(cat "$ef")
  rm -f "$ef"
}

contiene() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  return 1
}

# fuente_temporal: fuente mínima con este instalador/, pipeline.conf y un manifiesto de un archivo.
fuente_temporal() {
  local f
  f=$(mktemp -d "$tmp/fuente.XXXXXX")
  mkdir -p "$f/.claude"
  cp -r "$repo/instalador" "$f/instalador"
  cp "$repo/.claude/pipeline.conf" "$f/.claude/pipeline.conf"
  printf 'uno\n' > "$f/uno.txt"
  printf 'uno.txt\n' > "$f/instalador/manifiesto.txt"
  printf '%s' "$f"
}

# ===========================================================================
echo "== origen_github: dueño y repo desde la URL de origin"
# ===========================================================================

origen_da() {
  DUENO_ORIGIN='' REPO_ORIGIN=''
  origen_github "$1" || { echo "no reconoció $1"; return 1; }
  [ "$DUENO_ORIGIN/$REPO_ORIGIN" = "$2/$3" ] || { echo "dio $DUENO_ORIGIN/$REPO_ORIGIN"; return 1; }
}

origen_rechaza() {
  if origen_github "$1"; then
    echo "aceptó $1 como $DUENO_ORIGIN/$REPO_ORIGIN"
    return 1
  fi
  return 0
}

caso "https con .git" origen_da https://github.com/acme/demo.git acme demo
caso "https sin .git" origen_da https://github.com/acme/demo acme demo
caso "https con / final" origen_da https://github.com/acme/demo.git/ acme demo
caso "mayúsculas en el host, puntos y guiones en el repo" origen_da https://GitHub.com/Acme/Mi-Repo.v2.git Acme Mi-Repo.v2
caso "https con usuario y clave (no se imprime)" origen_da https://usuario:clave@github.com/acme/demo.git acme demo
caso "www.github.com" origen_da https://www.github.com/acme/demo.git acme demo
caso "ssh estilo scp" origen_da git@github.com:acme/demo.git acme demo
caso "ssh:// con puerto" origen_da ssh://git@github.com:22/acme/demo.git acme demo
caso "rechaza otro host" origen_rechaza https://gitlab.com/acme/demo.git
caso "rechaza un host que solo empieza con github.com" origen_rechaza https://github.com.otro.example/acme/demo.git
caso "rechaza github.com escondido en el usuario de otro host" origen_rechaza https://otro.example/x@github.com/acme/demo.git
caso "rechaza una ruta local POSIX" origen_rechaza /tmp/remotos/001.git
caso "rechaza una ruta local Windows" origen_rechaza C:/Users/x/remoto.git
caso "rechaza file://" origen_rechaza file:///github.com/acme/demo.git
caso "rechaza solo el dueño" origen_rechaza https://github.com/acme
caso "rechaza segmentos de más" origen_rechaza https://github.com/acme/demo/extra
caso "rechaza espacios en el repo" origen_rechaza 'https://github.com/acme/de mo.git'
caso "rechaza .. como repo" origen_rechaza https://github.com/acme/..
caso "rechaza la URL vacía" origen_rechaza ''

# ===========================================================================
echo "== nombres, puerto, comillas y plantillas"
# ===========================================================================

nombre_seguro_da() {
  nombre_seguro "$1"
  [ "$NOMBRE" = "$2" ] || { echo "'$1' dio '$NOMBRE', esperaba '$2'"; return 1; }
}
caso "nombre_seguro: deja un nombre seguro igual" nombre_seguro_da 001-c4-sin-origen 001-c4-sin-origen
caso "nombre_seguro: los espacios pasan a -" nombre_seguro_da 'mi repo' mi-repo
caso "nombre_seguro: quita . y - del comienzo" nombre_seguro_da '..-raro' raro
caso "nombre_seguro: los caracteres no ASCII pasan a -" nombre_seguro_da 'ñandú' and-
caso "nombre_seguro: vacío o solo guiones da proyecto" nombre_seguro_da '---' proyecto

acepta() { "$@" || { echo "rechazó: ${*:2}"; return 1; }; }
rechaza() { if "$@"; then echo "aceptó: ${*:2}"; return 1; fi; return 0; }
for v in miapi mi-api.v2 API_2; do caso "nombre_valido acepta $v" acepta nombre_valido "$v"; done
for v in 'a b' "a'b" -x .x '' ñ 'a;b'; do caso "nombre_valido rechaza '$v'" rechaza nombre_valido "$v"; done
for v in 8080 1 65535 08080; do caso "puerto_valido acepta $v" acepta puerto_valido "$v"; done
for v in 0 65536 abc '' 80a 123456 -1 ' 80'; do caso "puerto_valido rechaza '$v'" rechaza puerto_valido "$v"; done

citar_ida_y_vuelta() {
  local r
  citar "$1"
  eval "r=$CITADO"
  [ "$r" = "$1" ] || { echo "'$1' volvió como '$r' (citado: $CITADO)"; return 1; }
}
for v in 'a b' "it's" '$HOME' 'a"b' 'a\nb' "o'brien y 'más'"; do caso "citar ida y vuelta: $v" citar_ida_y_vuelta "$v"; done

palabra_da() {
  palabra "$1"
  [ "$PALABRA" = "$2" ] || { echo "'$1' dio $PALABRA"; return 1; }
}
caso "palabra: una rama simple queda igual" palabra_da trabajo trabajo
caso "palabra: una rama con / queda igual" palabra_da feat/T1-x feat/T1-x
caso "palabra: una rama con ; va entre comillas" palabra_da 'a;b' "'a;b'"
caso "palabra: una rama con \$ va entre comillas" palabra_da 'rama$x' "'rama\$x'"

rellenar_literal() {
  rellenar 'x {{a}} y {{a}} {{b}} {{c}}' a '&/\' b '$HOME'
  [ "$RELLENO" = 'x &/\ y &/\ $HOME {{c}}' ] || { echo "dio: $RELLENO"; return 1; }
}
caso "rellenar: reemplaza todas, en forma literal, y deja las claves que no recibe" rellenar_literal

# ===========================================================================
echo "== reglas de rutas y de modo"
# ===========================================================================

for v in README.md readme README LICENSE LICENSE.txt license.md .gitignore .gitattributes; do
  caso "es_archivo_de_repo_nuevo acepta $v" acepta es_archivo_de_repo_nuevo "$v"
done
for v in docs/README.md src/app.py package.json CLAUDE.md .github/CODEOWNERS; do
  caso "es_archivo_de_repo_nuevo rechaza $v" rechaza es_archivo_de_repo_nuevo "$v"
done
for v in CLAUDE.md .gitignore .claude/hooks/_lib.sh .github/workflows/ci.yml; do
  caso "ruta_relativa_valida acepta $v" acepta ruta_relativa_valida "$v"
done
for v in '' /abs ../x a/../b a/./b ./a a//b a/ 'a\b' C:x .git .git/config .GIT/config a/.. .; do
  caso "ruta_relativa_valida rechaza '$v'" rechaza ruta_relativa_valida "$v"
done

manifiesto_con_crlf_y_comentarios() {
  local f="$tmp/manifiesto-$RANDOM.txt"
  printf '# comentario\r\n\r\n  uno.txt  \r\n   # comentario con sangría\r\n\t\r\ncarpeta/dos.txt\r\nultimo.txt' > "$f"
  leer_manifiesto "$f"
  [ "${MANIFIESTO[*]}" = "uno.txt carpeta/dos.txt ultimo.txt" ] || { echo "dio: ${MANIFIESTO[*]}"; return 1; }
  [ "${#MANIFIESTO[@]}" -eq 3 ] || { echo "dio ${#MANIFIESTO[@]} rutas"; return 1; }
}
caso "leer_manifiesto: CRLF, comentarios, sangría, vacías y última línea sin salto" manifiesto_con_crlf_y_comentarios

leer_archivo_exacto() {
  local f="$tmp/exacto-$RANDOM"
  printf 'a\r\nb\\n\n\n' > "$f"
  leer_archivo "$f" || { echo "no leyó el archivo"; return 1; }
  [ "$CONTENIDO" = $'a\r\nb\\n\n\n' ] || { echo "el contenido no es exacto"; return 1; }
  : > "$f.vacio"
  leer_archivo "$f.vacio" && [ -z "$CONTENIDO" ] || { echo "falló con un archivo vacío"; return 1; }
  printf 'a\0b' > "$f.nul"
  rechaza leer_archivo "$f.nul" > /dev/null || { echo "aceptó un archivo con NUL"; return 1; }
  rechaza leer_archivo "$f.no-existe" > /dev/null || { echo "aceptó un archivo que no existe"; return 1; }
}
caso "leer_archivo: contenido exacto (\\r, \\ y saltos finales), vacío, NUL y ausente" leer_archivo_exacto

mismo_archivo_casos() {
  local f="$tmp/mismo-$RANDOM"
  printf 'x\n' > "$f.a"
  printf 'x\n' > "$f.b"
  printf 'x\r\n' > "$f.crlf"
  printf 'x\0y' > "$f.nul1"
  printf 'x\0y' > "$f.nul2"
  printf 'x\0z' > "$f.nul3"
  mismo_archivo "$f.a" "$f.b" || { echo "iguales dieron distinto"; return 1; }
  rechaza mismo_archivo "$f.a" "$f.crlf" > /dev/null || { echo "LF y CRLF dieron igual en una copia"; return 1; }
  mismo_archivo "$f.nul1" "$f.nul2" || { echo "binarios iguales dieron distinto"; return 1; }
  rechaza mismo_archivo "$f.nul1" "$f.nul3" > /dev/null || { echo "binarios distintos dieron igual"; return 1; }
  rechaza mismo_archivo "$f.a" "$f.nul1" > /dev/null || { echo "texto y binario dieron igual"; return 1; }
}
caso "mismo_archivo: exacto, sin tolerar CRLF en copias, y con NUL por cmp" mismo_archivo_casos

# Estado para detectar_modo y detectar_manifiestos: el manifiesto real de la fuente.
FUENTE=$repo
DIR_INSTALADOR="$repo/instalador"
leer_manifiesto "$DIR_INSTALADOR/manifiesto.txt"
validar_manifiesto

modo_de() {
  DESTINO=$1
  detectar_modo
  [ "$MODO_DETECTADO" = "$2" ] || { echo "dio $MODO_DETECTADO, esperaba $2"; return 1; }
}

modo_repo_vacio() {
  local d
  d=$(nuevo_repo vacio)
  modo_de "$d" nuevo
}
modo_framework_commiteado() {
  local d
  d=$(nuevo_repo framework)
  mkdir -p "$d/.claude" "$d/.pipeline" "$d/.railway"
  printf 'x\n' > "$d/CLAUDE.md"
  printf '{}\n' > "$d/.claude/settings.json"
  printf '{}\n' > "$d/.pipeline/plan.json"
  printf 'x\n' > "$d/.railway/railway.ts"
  printf 'x\n' > "$d/README.md"
  commit_todo "$d"
  modo_de "$d" nuevo
}
modo_readme_en_carpeta() {
  local d
  d=$(nuevo_repo readme-carpeta)
  mkdir -p "$d/docs"
  printf 'x\n' > "$d/docs/README.md"
  commit_todo "$d"
  modo_de "$d" existente
}
modo_sin_versionar() {
  local d
  d=$(nuevo_repo sin-versionar)
  mkdir -p "$d/src"
  printf 'x\n' > "$d/src/app.py"
  modo_de "$d" nuevo
}
modo_en_el_indice() {
  local d
  d=$(nuevo_repo indice)
  mkdir -p "$d/src"
  printf 'x\n' > "$d/src/app.py"
  g "$d" add src/app.py
  modo_de "$d" existente
}
caso "detectar_modo: repo vacío es nuevo" modo_repo_vacio
caso "detectar_modo: los archivos del framework ya commiteados no cuentan (sigue nuevo)" modo_framework_commiteado
caso "detectar_modo: README fuera de la raíz da existente" modo_readme_en_carpeta
caso "detectar_modo: un archivo sin versionar no cuenta" modo_sin_versionar
caso "detectar_modo: un archivo en el índice, sin commit, cuenta" modo_en_el_indice

manifiestos_en_carpetas() {
  local d
  d=$(nuevo_repo pistas)
  mkdir -p "$d/web" "$d/docs"
  printf '{}\n' > "$d/package.json"
  printf '{}\n' > "$d/web/package.json"
  printf 'FROM x\n' > "$d/Dockerfile"
  printf '{}\n' > "$d/mypackage.json"
  printf 'x\n' > "$d/docs/go.mod.md"
  commit_todo "$d"
  DESTINO=$d
  detectar_manifiestos
  [ "${PISTAS[*]}" = "Dockerfile package.json web/package.json" ] || { echo "dio: ${PISTAS[*]}"; return 1; }
}
caso "detectar_manifiestos: por nombre exacto y en cualquier carpeta" manifiestos_en_carpetas

# ===========================================================================
echo "== argumentos (de punta a punta)"
# ===========================================================================

e2e_ayuda() {
  correr "$instalador" --help
  [ "$CODIGO" -eq 0 ] || { echo "código $CODIGO"; return 1; }
  contiene "$SALIDA" "Uso: bash instalador/instalar.sh" || { echo "no imprimió el uso"; return 1; }
}

e2e_errores_de_uso() {
  local d antes args
  d=$(nuevo_repo errores)
  commit_todo "$d"
  antes=$(huella "$d")
  for args in "--puerto" "--puerto 0" "--puerto 65536" "--puerto=12a" "--servicio a;b" "--servicio -x" \
    "--modo" "--modo=raro" "otro-destino" "-- a b"; do
    # shellcheck disable=SC2086
    correr "$instalador" "$d" $args
    [ "$CODIGO" -eq 2 ] || { echo "'$args': código $CODIGO, esperaba 2"; return 1; }
    [ -n "$ERRSAL" ] || { echo "'$args': sin mensaje en stderr"; return 1; }
  done
  [ "$antes" = "$(huella "$d")" ] || { echo "un error de uso tocó el destino"; return 1; }
}

e2e_formas_de_opcion() {
  local d
  d=$(nuevo_repo formas)
  commit_todo "$d"
  correr "$instalador" --puerto=3000 --servicio=mi.api --modo=existente -- "$d"
  [ "$CODIGO" -eq 0 ] || { echo "código $CODIGO: $ERRSAL"; return 1; }
  contiene "$SALIDA" "modo existente" || { echo "no tomó --modo=existente"; return 1; }
  contiene "$SALIDA" "railway variable set PORT=3000 --service mi.api --environment production" \
    || { echo "no tomó --puerto= y --servicio="; return 1; }
  correr "$instalador" "$d" --puerto 08080
  contiene "$SALIDA" "PORT=8080 " || { echo "08080 no quedó como 8080"; return 1; }
}

e2e_subcarpeta() {
  local d
  d=$(nuevo_repo raiz)
  mkdir -p "$d/sub"
  printf 'x\n' > "$d/sub/a.txt"
  commit_todo "$d"
  correr "$instalador" "$d/sub"
  [ "$CODIGO" -eq 2 ] || { echo "código $CODIGO, esperaba 2"; return 1; }
  [ ! -e "$d/sub/CLAUDE.md" ] || { echo "escribió en la subcarpeta"; return 1; }
}

caso "--help sale 0 e imprime el uso" e2e_ayuda
caso "errores de uso (valores, repetidos, sobrantes) salen 2 y no tocan el destino" e2e_errores_de_uso
caso "--opcion=valor, -- antes del destino y --puerto con ceros a la izquierda" e2e_formas_de_opcion
caso "una subcarpeta de un repo no es un destino válido (sale 2)" e2e_subcarpeta

# ===========================================================================
echo "== fuente inválida (de punta a punta, con una fuente temporal)"
# ===========================================================================

e2e_fuente_invalida() {
  local f d antes linea
  d=$(nuevo_repo destino-fuente)
  commit_todo "$d"
  antes=$(huella "$d")
  for linea in '../fuera.txt' '/abs.txt' 'no-existe.txt' '.pipeline/plan.json' 'uno.txt' '.git/config'; do
    f=$(fuente_temporal)
    printf '%s\n' "$linea" >> "$f/instalador/manifiesto.txt"
    correr "$f/instalador/instalar.sh" "$d" --aplicar
    [ "$CODIGO" -eq 1 ] || { echo "manifiesto con '$linea': código $CODIGO, esperaba 1"; return 1; }
    [ -n "$ERRSAL" ] || { echo "manifiesto con '$linea': sin mensaje"; return 1; }
  done
  f=$(fuente_temporal)
  printf 'dueno=x\n' > "$f/.claude/pipeline.conf"
  correr "$f/instalador/instalar.sh" "$d" --aplicar
  [ "$CODIGO" -eq 1 ] || { echo "conf sin bot: código $CODIGO, esperaba 1"; return 1; }
  f=$(fuente_temporal)
  rm "$f/instalador/plantillas/railway.ts"
  correr "$f/instalador/instalar.sh" "$d" --aplicar
  [ "$CODIGO" -eq 1 ] || { echo "sin plantilla: código $CODIGO, esperaba 1"; return 1; }
  [ "$antes" = "$(huella "$d")" ] || { echo "una fuente inválida tocó el destino"; return 1; }
}

e2e_destino_es_la_fuente() {
  local f antes
  f=$(fuente_temporal)
  g "$f" init -q -b main
  commit_todo "$f"
  antes=$(huella "$f")
  correr "$f/instalador/instalar.sh" "$f" --aplicar
  [ "$CODIGO" -eq 2 ] || { echo "código $CODIGO, esperaba 2"; return 1; }
  [ "$antes" = "$(huella "$f")" ] || { echo "tocó la fuente"; return 1; }
}

caso "manifiesto, conf o plantilla inválidos salen 1 sin tocar el destino" e2e_fuente_invalida
caso "el destino no puede ser la propia fuente (sale 2)" e2e_destino_es_la_fuente

# ===========================================================================
echo "== archivos, conflictos y rama (de punta a punta)"
# ===========================================================================

e2e_padre_es_archivo() {
  local d
  d=$(nuevo_repo padre-archivo)
  printf 'soy un archivo\n' > "$d/.claude"
  commit_todo "$d"
  correr "$instalador" "$d" --aplicar
  [ "$CODIGO" -eq 3 ] || { echo "código $CODIGO, esperaba 3"; return 1; }
  contiene "$SALIDA" "conflicto .claude/settings.json" || { echo "no marcó conflicto bajo .claude"; return 1; }
  [ "$(cat "$d/.claude")" = "soy un archivo" ] || { echo "tocó el archivo .claude"; return 1; }
  [ -f "$d/CLAUDE.md" ] || { echo "no escribió los demás archivos"; return 1; }
}

# bloque_diff: de SALIDA, las líneas desde "diff - " hasta "GENERADO".
bloque_diff() {
  local linea dentro=0
  while IFS= read -r linea; do
    case "$linea" in
      'diff - '*) dentro=1 ;;
    esac
    [ "$dentro" -eq 1 ] && printf '%s\n' "$linea"
    [ "$dentro" -eq 1 ] && [ "$linea" = GENERADO ] && break
  done <<< "$SALIDA"
  return 0
}

e2e_conflicto_generado() {
  local d bloque salida_diff codigo_diff
  d=$(nuevo_repo "con 'comillas' y espacios")
  commit_todo "$d"
  mkdir -p "$d/.railway"
  printf '// distinto\n' > "$d/.railway/railway.ts"
  correr "$instalador" "$d"
  [ "$CODIGO" -eq 3 ] || { echo "código $CODIGO, esperaba 3"; return 1; }
  bloque=$(bloque_diff)
  [ -n "$bloque" ] || { echo "no imprimió el diff del archivo generado"; return 1; }
  salida_diff=$(cd "$tmp" && bash -c "$bloque" 2>&1)
  codigo_diff=$?
  [ "$codigo_diff" -eq 1 ] || { echo "el diff impreso no corre bien (código $codigo_diff): $salida_diff"; return 1; }
  contiene "$salida_diff" "// distinto" || { echo "el diff no muestra el archivo del destino"; return 1; }
  contiene "$salida_diff" "restartPolicyMaxRetries: 3" || { echo "el diff no muestra el contenido generado"; return 1; }
}

e2e_generado_crlf_es_igual() {
  local a b
  a=$(nuevo_repo base-crlf)
  commit_todo "$a"
  bash "$instalador" "$a" --aplicar > /dev/null 2>&1
  b=$(nuevo_repo destino-crlf)
  commit_todo "$b"
  mkdir -p "$b/.railway"
  local linea
  while IFS= read -r linea || [ -n "$linea" ]; do
    printf '%s\r\n' "$linea"
  done < "$a/.railway/railway.ts" > "$b/.railway/railway.ts"
  correr "$instalador" "$b"
  contiene "$SALIDA" "igual .railway/railway.ts" || { echo "un railway.ts con CRLF no contó como igual"; return 1; }
}

e2e_cd_con_comillas() {
  local d linea esperado
  d=$(nuevo_repo "o'brien y espacios")
  commit_todo "$d"
  correr "$instalador" "$d"
  linea=$(printf '%s\n' "$SALIDA" | grep -m1 '^cd ')
  esperado=$(cd "$d" && pwd)
  [ "$(eval "$linea" && pwd)" = "$esperado" ] || { echo "la línea '$linea' no lleva al destino"; return 1; }
}

e2e_idempotente_despues_del_commit() {
  local d
  d=$(nuevo_repo idempotente)
  commit_todo "$d"
  bash "$instalador" "$d" --aplicar > /dev/null 2>&1
  commit_todo "$d" framework
  correr "$instalador" "$d" --aplicar
  [ "$CODIGO" -eq 0 ] || { echo "código $CODIGO, esperaba 0"; return 1; }
  contiene "$SALIDA" "modo nuevo" || { echo "cambió de modo después de commitear el framework"; return 1; }
  printf '%s\n' "$SALIDA" | grep -q '^crear ' && { echo "quiso crear algo después del commit"; return 1; }
  [ ! -e "$d/.pipeline/criterios-T1.md" ] || { echo "generó criterios-T1.md en un repo nuevo"; return 1; }
  return 0
}

e2e_existente_sin_manifiestos() {
  local d
  d=$(nuevo_repo sin-manifiestos)
  mkdir -p "$d/src"
  printf 'x\n' > "$d/src/main.c"
  commit_todo "$d"
  correr "$instalador" "$d" --aplicar
  grep -q "Ninguno de los conocidos" "$d/.pipeline/criterios-T1.md" || { echo "no dijo que no hay manifiestos conocidos"; return 1; }
  grep -q '{{' "$d/.pipeline/criterios-T1.md" "$d/.pipeline/plan.json" "$d/.railway/railway.ts" \
    "$d/.pipeline/lecciones-pendientes.md" && { echo "quedó una clave {{...}} sin reemplazar"; return 1; }
  return 0
}

e2e_staging_solo_en_origin() {
  local d
  d=$(nuevo_repo remoto-staging)
  commit_todo "$d"
  g "$d" update-ref refs/remotes/origin/staging HEAD
  correr "$instalador" "$d" --aplicar
  contiene "$SALIDA" "rama staging: existe" || { echo "no reportó 'existe'"; return 1; }
  contiene "$SALIDA" "origin/staging" || { echo "no explicó que existe en origin"; return 1; }
  if g "$d" show-ref --verify --quiet refs/heads/staging; then
    echo "creó una staging local que podría divergir de origin/staging"
    return 1
  fi
  return 0
}

e2e_activa_staging() {
  local d
  d=$(nuevo_repo activa-staging staging)
  commit_todo "$d"
  correr "$instalador" "$d" --aplicar
  contiene "$SALIDA" "rama staging: existe" || { echo "no reportó 'existe'"; return 1; }
  contiene "$SALIDA" "git push -u origin staging" || { echo "no empuja staging"; return 1; }
  contiene "$SALIDA" "merge --ff-only" && { echo "hace merge de staging sobre sí misma"; return 1; }
  return 0
}

e2e_head_separado() {
  local d
  d=$(nuevo_repo separado)
  commit_todo "$d"
  g "$d" switch -q --detach HEAD
  correr "$instalador" "$d" --aplicar
  [ "$CODIGO" -eq 0 ] || { echo "código $CODIGO: $ERRSAL"; return 1; }
  contiene "$SALIDA" "HEAD separado" || { echo "no avisó del HEAD separado"; return 1; }
  g "$d" show-ref --verify --quiet refs/heads/staging || { echo "no creó staging"; return 1; }
}

e2e_rama_rara() {
  local d
  d=$(nuevo_repo rama-rara 'rama$rara')
  commit_todo "$d"
  correr "$instalador" "$d"
  contiene "$SALIDA" "git push -u origin 'rama\$rara' staging" || { echo "no citó la rama activa"; return 1; }
}

e2e_origin_no_github_y_sin_origin() {
  local d
  d=$(nuevo_repo otro-host)
  g "$d" remote set-url origin https://usuario:secreto@gitlab.example/acme/demo.git
  commit_todo "$d"
  correr "$instalador" "$d"
  contiene "$SALIDA" "secreto" && { echo "imprimió la URL de origin con su clave"; return 1; }
  contiene "$SALIDA" "origin no apunta a un repo de github.com" || { echo "no avisó del origin"; return 1; }
  contiene "$SALIDA" "/otro-host, servicio: otro-host" || { echo "no usó la carpeta como repo"; return 1; }
  g "$d" remote remove origin
  correr "$instalador" "$d"
  contiene "$SALIDA" "git remote add origin https://github.com/" || { echo "sin origin no dijo cómo agregarlo"; return 1; }
  contiene "$SALIDA" "/otro-host.git" || { echo "el origin sugerido no usa el nombre de la carpeta"; return 1; }
}

e2e_nota_de_dueno() {
  local d dueno_conf
  dueno_conf=$(sed -n 's/^dueno=//p' "$repo/.claude/pipeline.conf" | tr -d '\r' | head -1)
  d=$(nuevo_repo dueno-distinto)
  commit_todo "$d"
  correr "$instalador" "$d"
  contiene "$SALIDA" "el dueño del repo (acme) no es el de .claude/pipeline.conf" || { echo "no avisó del dueño distinto"; return 1; }
  g "$d" remote set-url origin "https://github.com/$dueno_conf/demo.git"
  correr "$instalador" "$d"
  contiene "$SALIDA" "no es el de .claude/pipeline.conf" && { echo "avisó con el mismo dueño"; return 1; }
  return 0
}

caso "una carpeta intermedia que es archivo da conflicto y no se toca" e2e_padre_es_archivo
caso "el diff impreso de un archivo generado en conflicto corre y muestra las dos versiones" e2e_conflicto_generado
caso "un archivo generado que solo cambia en CRLF cuenta como igual" e2e_generado_crlf_es_igual
caso "la línea cd de los pasos lleva al destino aunque tenga comillas y espacios" e2e_cd_con_comillas
caso "después de commitear el framework, otra corrida da el mismo modo y todo igual" e2e_idempotente_despues_del_commit
caso "modo existente sin manifiestos conocidos lo dice, y no quedan claves {{...}}" e2e_existente_sin_manifiestos
caso "staging solo en origin cuenta como existe y no crea la local" e2e_staging_solo_en_origin
caso "con staging activa, empuja staging sin merge sobre sí misma" e2e_activa_staging
caso "con HEAD separado avisa, y crea staging en HEAD" e2e_head_separado
caso "una rama activa con caracteres raros va entre comillas en los pasos" e2e_rama_rara
caso "origin fuera de GitHub no se imprime y sin origin se sugiere cómo agregarlo" e2e_origin_no_github_y_sin_origin
caso "la nota del dueño distinto sale solo cuando el dueño cambia" e2e_nota_de_dueno

echo
echo "$ok ok, $fallos fallos"
[ "$fallos" -eq 0 ]
