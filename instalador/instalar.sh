#!/usr/bin/env bash
# Instalador del framework de agentes (T3b; B para repos de la organización; criterios en
# .pipeline/criterios-T3b.md y .pipeline/criterios-B.md).
#
# Uso: bash instalador/instalar.sh <destino> [--aplicar] [--modo nuevo|existente] [--servicio NOMBRE] [--puerto N]
#
# Copia a <destino>, la raíz de un repo git, los archivos del framework que lista
# instalador/manifiesto.txt y genera los archivos propios del destino (.pipeline/lecciones-pendientes.md,
# .pipeline/plan.json, .pipeline/criterios-T1.md en modo existente, .railway/railway.ts y
# .claude/identidad-agente.txt, con el bot de .claude/pipeline.conf) desde instalador/plantillas/. La
# fuente del framework es el repo donde vive este script: el padre de instalador/.
#
# - Sin --aplicar solo simula: imprime el plan completo y no escribe nada en el destino.
# - Con --aplicar escribe solo los archivos que no existen. Un archivo que ya existe con otro
#   contenido es un conflicto y no se toca.
# - Nunca crea, mueve ni borra ramas (staging nace en el servidor, después del PR T0 de /crear-repo),
#   nunca hace commit, push ni fetch, y no llama a gh ni a railway: los pasos que le tocan a una persona
#   los imprime, con los valores ya reemplazados, después de "== Pasos manuales".
# - Un destino cuyo origin es de github.com/<org> (org de .claude/pipeline.conf) no lleva notas si no
#   hay nada raro; uno que no es de la organización lo dice en una nota.
#
# Salida estándar: "crear|igual|conflicto <ruta>" por archivo (ruta relativa al destino, con /),
# "modo nuevo|existente", "rama staging: existe|no se crea", las notas ("nota: ...") y los pasos
# manuales. Códigos de salida: 0 sin conflictos; 3 con al menos un conflicto; 2 error de uso, sin tocar
# el destino; 1 error de la fuente (manifiesto, configuración o plantillas inválidos) o una escritura
# que falló.
#
# Portabilidad: bash 4.4 o más, coreutils y git, sin awk ni sed. Git Bash para Windows y Linux, y
# rutas con espacios. Las plantillas se leen sin \r: el resultado no depende de core.autocrlf.
set -uo pipefail

USO='Uso: bash instalador/instalar.sh <destino> [--aplicar] [--modo nuevo|existente] [--servicio NOMBRE] [--puerto N]'
# Caracteres de nombres de repo, dueño, bot y servicio. Lista explícita y no rangos: los rangos
# dependen del locale.
SEGUROS='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-'
# Manifiestos que se nombran como pistas en los criterios del ADR del stack actual (C5).
MANIFIESTOS_CONOCIDOS=(package.json pyproject.toml go.mod requirements.txt Cargo.toml Gemfile Dockerfile)
MAX_PISTAS=20
# Archivos que genera el instalador. Nunca van en el manifiesto.
GENERADOS=(.pipeline/lecciones-pendientes.md .pipeline/plan.json .pipeline/criterios-T1.md .railway/railway.ts .claude/identidad-agente.txt)

# ---------------------------------------------------------------------------
# errores
# ---------------------------------------------------------------------------

error_uso() {
  printf 'instalar.sh: %s\n%s\n' "$1" "$USO" >&2
  exit 2
}

error_fuente() {
  printf 'instalar.sh: %s\n' "$1" >&2
  exit 1
}

ayuda() {
  printf '%s\n' "$USO" '' \
    'Sin --aplicar solo simula: imprime el plan y no escribe nada en el destino.' \
    '  --aplicar          escribe los archivos que no existen (no crea ramas)' \
    '  --modo M           fuerza el modo: nuevo o existente (por defecto se detecta)' \
    '  --servicio NOMBRE  servicio de Railway (por defecto, el nombre del repo)' \
    '  --puerto N         puerto de la app en Railway (por defecto 8080)' \
    'Códigos de salida: 0 sin conflictos, 3 con conflictos, 2 error de uso, 1 error de la fuente.'
}

# ---------------------------------------------------------------------------
# utilidades puras (las prueba tests/unit/test-instalar.sh)
# ---------------------------------------------------------------------------

# solo_seguros <s>: 0 si <s> no está vacío y solo tiene letras ASCII, dígitos, ".", "_" y "-".
solo_seguros() {
  [ -n "$1" ] && [ -z "${1//[$SEGUROS]/}" ]
}

# nombre_valido <s>: nombre de servicio; seguro y sin ".", "_" ni "-" al comienzo.
nombre_valido() {
  solo_seguros "$1" || return 1
  case "${1:0:1}" in
    [._-]) return 1 ;;
  esac
  return 0
}

# nombre_seguro <s>: deja en NOMBRE un nombre de repo hecho a partir de un nombre de carpeta: cada
# carácter no seguro pasa a "-" y se quitan ".", "_" y "-" del comienzo. Vacío queda "proyecto".
nombre_seguro() {
  local s=${1//[^$SEGUROS]/-}
  while [ -n "$s" ]; do
    case "${s:0:1}" in
      [._-]) s=${s:1} ;;
      *) break ;;
    esac
  done
  NOMBRE=${s:-proyecto}
}

# puerto_valido <s>: 0 si <s> es un número entre 1 y 65535.
puerto_valido() {
  case "$1" in
    '' | *[!0123456789]*) return 1 ;;
  esac
  [ "${#1}" -le 5 ] || return 1
  [ $((10#$1)) -ge 1 ] && [ $((10#$1)) -le 65535 ]
}

# citar <s>: deja en CITADO <s> entre comillas simples, lista para pegar en bash.
citar() {
  CITADO="'${1//\'/\'\\\'\'}'"
}

# rellenar <texto> [clave valor]...: deja en RELLENO el texto con cada {{clave}} cambiado por su
# valor, en forma literal (el valor entre comillas: "&", "/" y "\" no son especiales).
rellenar() {
  local texto=$1 clave
  shift
  while [ $# -ge 2 ]; do
    clave="{{$1}}"
    texto=${texto//"$clave"/"$2"}
    shift 2
  done
  RELLENO=$texto
}

# origen_github <url>: si <url> es la de un repo de github.com (https, http, ssh, git o la forma
# usuario@github.com:dueño/repo), deja DUENO_ORIGIN y REPO_ORIGIN y sale 0. Si no, sale 1.
origen_github() {
  local url=${1%/} resto autoridad host dueno repo
  case "$url" in
    *://*)
      case "${url%%://*}" in
        https | http | ssh | git) ;;
        *) return 1 ;;
      esac
      resto=${url#*://}
      autoridad=${resto%%/*}
      [ "$autoridad" != "$resto" ] || return 1
      resto=${resto#*/}
      host=${autoridad##*@}
      host=${host%%:*}
      ;;
    *:*)
      autoridad=${url%%:*}
      case "$autoridad" in
        */*) return 1 ;;
      esac
      resto=${url#*:}
      host=${autoridad##*@}
      ;;
    *) return 1 ;;
  esac
  case "${host,,}" in
    github.com | www.github.com) ;;
    *) return 1 ;;
  esac
  resto=${resto%/}
  resto=${resto%.git}
  case "$resto" in
    */*/* | /* | */) return 1 ;;
    */*) ;;
    *) return 1 ;;
  esac
  dueno=${resto%%/*}
  repo=${resto#*/}
  solo_seguros "$dueno" && solo_seguros "$repo" || return 1
  case "$repo" in
    . | ..) return 1 ;;
  esac
  DUENO_ORIGIN=$dueno
  REPO_ORIGIN=$repo
}

# es_archivo_de_repo_nuevo <ruta>: 0 si la ruta versionada no impide el modo nuevo: README*,
# LICENSE*, .gitignore o .gitattributes en la raíz (sin distinguir mayúsculas).
es_archivo_de_repo_nuevo() {
  case "$1" in
    */*) return 1 ;;
  esac
  case "${1,,}" in
    readme* | license* | .gitignore | .gitattributes) return 0 ;;
  esac
  return 1
}

# ruta_relativa_valida <ruta>: 0 si es una ruta relativa limpia que queda dentro del repo y fuera de .git.
ruta_relativa_valida() {
  case "$1" in
    '' | /* | *\\* | *:* | . | .. | ./* | ../* | */. | */.. | */./* | */../* | *//* | */) return 1 ;;
  esac
  case "${1,,}" in
    .git | .git/*) return 1 ;;
  esac
  return 0
}

# leer_manifiesto <archivo>: deja en MANIFIESTO las rutas, sin comentarios (#), sin líneas vacías,
# sin \r y sin los espacios de los extremos.
leer_manifiesto() {
  local linea
  MANIFIESTO=()
  while IFS= read -r linea || [ -n "$linea" ]; do
    linea=${linea//$'\r'/}
    linea=${linea#"${linea%%[![:space:]]*}"}
    linea=${linea%"${linea##*[![:space:]]}"}
    case "$linea" in
      '' | '#'*) continue ;;
    esac
    MANIFIESTO+=("$linea")
  done < "$1"
}

# leer_archivo <archivo>: deja en CONTENIDO el contenido exacto del archivo. Sale 1 si no se puede
# leer o si tiene un byte NUL (no es texto).
leer_archivo() {
  CONTENIDO=''
  [ -f "$1" ] && [ -r "$1" ] || return 1
  # read devuelve 0 solo si encontró el delimitador NUL; al llegar al final devuelve 1.
  if IFS= read -r -d '' CONTENIDO < "$1"; then
    CONTENIDO=''
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# argumentos, fuente y destino
# ---------------------------------------------------------------------------

asignar_opcion() {
  case "$1" in
    --modo)
      case "$2" in
        nuevo | existente) MODO_FORZADO=$2 ;;
        *) error_uso "--modo debe ser nuevo o existente, no '$2'" ;;
      esac
      ;;
    --servicio)
      nombre_valido "$2" || error_uso "--servicio solo admite letras, dígitos, '.', '_' y '-', y empieza con letra o dígito: '$2'"
      SERVICIO=$2
      ;;
    --puerto)
      puerto_valido "$2" || error_uso "--puerto debe ser un número entre 1 y 65535, no '$2'"
      PUERTO=$((10#$2))
      ;;
  esac
}

analizar_argumentos() {
  DESTINO_ARG='' APLICAR=0 MODO_FORZADO='' SERVICIO='' PUERTO=8080
  local hay_destino=0
  [ $# -gt 0 ] || error_uso "falta el destino"
  while [ $# -gt 0 ]; do
    case "$1" in
      --aplicar) APLICAR=1 ;;
      --modo | --servicio | --puerto)
        [ $# -ge 2 ] || error_uso "$1 necesita un valor"
        asignar_opcion "$1" "$2"
        shift
        ;;
      --modo=* | --servicio=* | --puerto=*) asignar_opcion "${1%%=*}" "${1#*=}" ;;
      -h | --help)
        ayuda
        exit 0
        ;;
      --)
        shift
        [ $# -le 1 ] || error_uso "sobran argumentos después de --"
        if [ $# -eq 1 ]; then
          [ "$hay_destino" -eq 0 ] || error_uso "sobra el argumento: $1"
          DESTINO_ARG=$1
          hay_destino=1
        fi
        break
        ;;
      -*) error_uso "opción desconocida: $1" ;;
      *)
        [ "$hay_destino" -eq 0 ] || error_uso "sobra el argumento: $1"
        DESTINO_ARG=$1
        hay_destino=1
        ;;
    esac
    shift
  done
  [ "$hay_destino" -eq 1 ] || error_uso "falta el destino"
  [ -n "$DESTINO_ARG" ] || error_uso "el destino está vacío"
}

ubicar_fuente() {
  local script=${BASH_SOURCE[0]} dir
  case "$script" in
    */*) dir=${script%/*} ;;
    *) dir=. ;;
  esac
  DIR_INSTALADOR=$(cd -- "$dir" && pwd) || error_fuente "no pude ubicar la carpeta del instalador"
  FUENTE=$(cd -- "$DIR_INSTALADOR/.." && pwd) || error_fuente "no pude ubicar la fuente del framework"
}

# git_destino <args>: git sobre el destino. main hace cd al destino una vez y git hereda ese
# directorio. No se usa git -C: en Git Bash, una ruta POSIX con comillas simples no llega convertida
# a git.exe, pero el directorio de trabajo sí.
git_destino() {
  if [ "$PWD" = "$DESTINO" ]; then
    git "$@"
  else
    (cd -- "$DESTINO" && git "$@")
  fi
}

validar_destino() {
  local salida
  [ -e "$DESTINO_ARG" ] || error_uso "el destino no existe: $DESTINO_ARG"
  [ -d "$DESTINO_ARG" ] || error_uso "el destino no es una carpeta: $DESTINO_ARG"
  DESTINO=$(cd -- "$DESTINO_ARG" && pwd) || error_uso "no pude entrar al destino: $DESTINO_ARG"
  salida=$(git_destino rev-parse --is-inside-work-tree --show-prefix 2>&1) ||
    error_uso "el destino no es un repo git: $DESTINO (git: ${salida%%$'\n'*})"
  case "$salida" in
    true) ;;
    true$'\n'*) error_uso "el destino está dentro de un repo git, pero no es su raíz: $DESTINO" ;;
    *) error_uso "el destino no es un repo git con árbol de trabajo: $DESTINO" ;;
  esac
  [ ! "$DESTINO" -ef "$FUENTE" ] || error_uso "el destino es la propia fuente del framework: $DESTINO"
}

# leer_conf: bot, dueño y organización de .claude/pipeline.conf de la fuente (la primera línea de
# cada clave).
leer_conf() {
  local f="$FUENTE/.claude/pipeline.conf" linea
  BOT='' DUENO_CONF='' ORG=''
  [ -f "$f" ] || error_fuente "falta la configuración del framework: $f"
  while IFS= read -r linea || [ -n "$linea" ]; do
    linea=${linea//$'\r'/}
    case "$linea" in
      bot=*) [ -n "$BOT" ] || BOT=${linea#bot=} ;;
      dueno=*) [ -n "$DUENO_CONF" ] || DUENO_CONF=${linea#dueno=} ;;
      org=*) [ -n "$ORG" ] || ORG=${linea#org=} ;;
    esac
  done < "$f"
  solo_seguros "$BOT" || error_fuente "$f no define un bot válido (bot=<login>)"
  solo_seguros "$DUENO_CONF" || error_fuente "$f no define un dueño válido (dueno=<login>)"
  solo_seguros "$ORG" || error_fuente "$f no define una organización válida (org=<login>)"
}

# validar_manifiesto: cada ruta es relativa y limpia, no se repite, no es un archivo generado y
# existe como archivo en la fuente. Deja en GESTIONADOS las rutas que maneja el instalador.
validar_manifiesto() {
  local r
  unset GESTIONADOS
  declare -gA GESTIONADOS=()
  for r in "${GENERADOS[@]}"; do
    GESTIONADOS[$r]=1
  done
  [ ${#MANIFIESTO[@]} -gt 0 ] || error_fuente "el manifiesto no lista ninguna ruta"
  for r in "${MANIFIESTO[@]}"; do
    ruta_relativa_valida "$r" || error_fuente "ruta inválida en el manifiesto: $r"
    [ -z "${GESTIONADOS[$r]+x}" ] || error_fuente "ruta repetida o reservada a un archivo generado en el manifiesto: $r"
    [ -f "$FUENTE/$r" ] || error_fuente "la ruta del manifiesto no es un archivo de la fuente: $r"
    GESTIONADOS[$r]=1
  done
}

# identificar_repo: dueño y repo desde origin (github.com). Sin origin de GitHub, el repo sale del
# nombre de la carpeta y el dueño de pipeline.conf. Nunca imprime la URL: podría traer credenciales.
# Deja DE_ORG en 1 si el dueño del origin es la organización de pipeline.conf (sin distinguir
# mayúsculas). Solo los repos que no son de la organización llevan notas de dueño y de destino: el code
# owner de un repo de la organización sigue siendo dueno=, aunque el dueño del origin sea la organización.
identificar_repo() {
  local url
  TIENE_ORIGIN=0
  DE_ORG=0
  url=$(git_destino remote get-url origin 2>/dev/null) && TIENE_ORIGIN=1
  if [ "$TIENE_ORIGIN" -eq 1 ] && origen_github "$url"; then
    DUENO=$DUENO_ORIGIN
    REPO=$REPO_ORIGIN
    ORIGIN_GITHUB=1
    [ "${DUENO,,}" != "${ORG,,}" ] || DE_ORG=1
  else
    ORIGIN_GITHUB=0
    nombre_seguro "${DESTINO##*/}"
    REPO=$NOMBRE
    DUENO=$DUENO_CONF
    if [ "$TIENE_ORIGIN" -eq 1 ]; then
      NOTAS+=("origin no apunta a un repo de github.com: el repo sale del nombre de la carpeta ($REPO) y el dueño de .claude/pipeline.conf ($DUENO).")
    else
      NOTAS+=("sin origin: el repo sale del nombre de la carpeta ($REPO) y el dueño de .claude/pipeline.conf ($DUENO).")
    fi
  fi
  [ "$DE_ORG" -eq 0 ] || return 0
  if [ "${DUENO,,}" != "${DUENO_CONF,,}" ]; then
    NOTAS+=("el dueño del repo ($DUENO) no es el de .claude/pipeline.conf ($DUENO_CONF): antes de commitear el framework, cambia dueno= en .claude/pipeline.conf y @$DUENO_CONF en .github/CODEOWNERS.")
  fi
  NOTAS+=("el destino no es un repo de $ORG: el framework se instala, pero la protección de ramas la dan los rulesets de la organización y aquí no aplican (CLAUDE.md, Repos en la organización).")
}

# ---------------------------------------------------------------------------
# modo y archivos generados
# ---------------------------------------------------------------------------

# detectar_modo: nuevo si los archivos versionados son solo README*, LICENSE*, .gitignore o
# .gitattributes de la raíz; existente con cualquier otro. Las rutas que maneja el instalador (las
# del manifiesto y las generadas) no cuentan: así, correrlo otra vez después de commitear el
# framework da el mismo modo y el mismo plan.json.
detectar_modo() {
  local f
  MODO_DETECTADO=nuevo
  while IFS= read -r -d '' f; do
    [ -z "${GESTIONADOS[$f]+x}" ] || continue
    es_archivo_de_repo_nuevo "$f" && continue
    MODO_DETECTADO=existente
    break
  done < <(git_destino ls-files -z 2>/dev/null)
}

# detectar_manifiestos: deja en PISTAS los manifiestos conocidos versionados, en cualquier carpeta.
detectar_manifiestos() {
  local f n specs=()
  PISTAS=()
  for n in "${MANIFIESTOS_CONOCIDOS[@]}"; do
    specs+=(":(glob)**/$n")
  done
  while IFS= read -r -d '' f; do
    PISTAS+=("$f")
  done < <(git_destino ls-files -z -- "${specs[@]}" 2>/dev/null)
}

# leer_plantilla <nombre>: deja en PLANTILLA el contenido de instalador/plantillas/<nombre>, sin \r.
leer_plantilla() {
  leer_archivo "$DIR_INSTALADOR/plantillas/$1" || error_fuente "falta o no se puede leer la plantilla instalador/plantillas/$1"
  PLANTILLA=${CONTENIDO//$'\r'/}
}

# agregar_generado <ruta> <contenido>
agregar_generado() {
  GEN_RUTAS+=("$1")
  GEN_CONTENIDOS+=("$2")
}

generar() {
  local lista='' p n=0
  GEN_RUTAS=()
  GEN_CONTENIDOS=()

  leer_plantilla lecciones-pendientes.md
  rellenar "$PLANTILLA" bot "$BOT"
  agregar_generado .pipeline/lecciones-pendientes.md "$RELLENO"

  if [ "$MODO" = nuevo ]; then
    leer_plantilla plan-nuevo.json
  else
    leer_plantilla plan-existente.json
  fi
  rellenar "$PLANTILLA" repo "$REPO"
  agregar_generado .pipeline/plan.json "$RELLENO"

  if [ "$MODO" = existente ]; then
    detectar_manifiestos
    for p in "${PISTAS[@]}"; do
      n=$((n + 1))
      if [ "$n" -gt "$MAX_PISTAS" ]; then
        lista+="- y $((${#PISTAS[@]} - MAX_PISTAS)) más."$'\n'
        break
      fi
      lista+="- \`$p\`"$'\n'
    done
    if [ -z "$lista" ]; then
      lista="- Ninguno de los conocidos (${MANIFIESTOS_CONOCIDOS[*]}): identifica el stack a mano."$'\n'
    fi
    leer_plantilla criterios-T1.md
    rellenar "$PLANTILLA" manifiestos "${lista%$'\n'}"
    agregar_generado .pipeline/criterios-T1.md "$RELLENO"
  fi

  leer_plantilla railway.ts
  rellenar "$PLANTILLA" repo "$REPO" servicio "$SERVICIO"
  agregar_generado .railway/railway.ts "$RELLENO"

  # La identidad que exige el hook: una sola línea, el bot de pipeline.conf.
  agregar_generado .claude/identidad-agente.txt "$BOT"$'\n'
}

# ---------------------------------------------------------------------------
# comparar y escribir
# ---------------------------------------------------------------------------

# padres_libres <ruta>: 0 si ninguna carpeta intermedia de la ruta en el destino es un archivo o
# un enlace simbólico (escribir ahí saldría del destino o pisaría un archivo).
padres_libres() {
  local resto=$1 prefijo=''
  while [ "${resto#*/}" != "$resto" ]; do
    prefijo+=${resto%%/*}
    resto=${resto#*/}
    if [ -L "$DESTINO/$prefijo" ]; then
      return 1
    fi
    if [ -e "$DESTINO/$prefijo" ] && [ ! -d "$DESTINO/$prefijo" ]; then
      return 1
    fi
    prefijo+=/
  done
  return 0
}

# mismo_archivo <a> <b>: 0 si los dos archivos tienen exactamente el mismo contenido. Compara en
# memoria, sin un proceso por archivo (en Git Bash cada proceso cuesta); un archivo con NUL va a cmp.
mismo_archivo() {
  local a
  if leer_archivo "$1"; then
    a=$CONTENIDO
    leer_archivo "$2" && [ "$a" = "$CONTENIDO" ]
    return
  fi
  cmp -s -- "$1" "$2"
}

# evaluar_copia <ruta> <archivo de la fuente>: deja ESTADO en crear, igual o conflicto.
evaluar_copia() {
  local dst="$DESTINO/$1"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ -f "$dst" ] && mismo_archivo "$2" "$dst"; then
      ESTADO=igual
    else
      ESTADO=conflicto
    fi
  elif padres_libres "$1"; then
    ESTADO=crear
  else
    ESTADO=conflicto
  fi
}

# evaluar_generado <ruta> <contenido>: como evaluar_copia, pero contra un contenido en memoria. Un
# archivo que solo difiere en los finales de línea (CRLF por core.autocrlf) cuenta como igual.
evaluar_generado() {
  local dst="$DESTINO/$1"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if leer_archivo "$dst" && { [ "$CONTENIDO" = "$2" ] || [ "${CONTENIDO//$'\r'/}" = "$2" ]; }; then
      ESTADO=igual
    else
      ESTADO=conflicto
    fi
  elif padres_libres "$1"; then
    ESTADO=crear
  else
    ESTADO=conflicto
  fi
}

# crear_carpeta_de <archivo>: crea la carpeta del archivo si falta.
crear_carpeta_de() {
  local dir=${1%/*}
  [ -d "$dir" ] || mkdir -p -- "$dir"
}

# copiar_pendientes: copia de la fuente al destino las rutas de A_COPIAR, con un solo mkdir para
# todas las carpetas que faltan y un cp por carpeta (el nombre del archivo es el mismo en los dos
# lados). cp conserva los permisos de la fuente, como el bit de ejecución de los scripts.
copiar_pendientes() {
  local r carpeta actual='' faltan=()
  local -A vistas=()
  GRUPO=() RUTAS_GRUPO=()
  [ ${#A_COPIAR[@]} -gt 0 ] || return 0
  for r in "${A_COPIAR[@]}"; do
    carpeta_de "$r"
    if [ -z "${vistas[x$CARPETA]+x}" ]; then
      vistas[x$CARPETA]=1
      [ -d "$DESTINO${CARPETA:+/$CARPETA}" ] || faltan+=("$DESTINO/$CARPETA")
    fi
  done
  if [ ${#faltan[@]} -gt 0 ] && ! mkdir -p -- "${faltan[@]}"; then
    for r in "${A_COPIAR[@]}"; do
      fallo_escritura "$r"
    done
    return 0
  fi
  # Un cp por cada tramo de rutas seguidas con la misma carpeta (el manifiesto viene agrupado).
  for r in "${A_COPIAR[@]}"; do
    carpeta_de "$r"
    if [ ${#GRUPO[@]} -gt 0 ] && [ "$CARPETA" != "$actual" ]; then
      copiar_grupo "$actual"
    fi
    actual=$CARPETA
    GRUPO+=("$FUENTE/$r")
    RUTAS_GRUPO+=("$r")
  done
  copiar_grupo "$actual"
}

# carpeta_de <ruta>: deja en CARPETA la carpeta de la ruta relativa, vacía si está en la raíz.
carpeta_de() {
  case "$1" in
    */*) CARPETA=${1%/*} ;;
    *) CARPETA='' ;;
  esac
}

# copiar_grupo <carpeta>: copia los archivos de GRUPO a esa carpeta del destino y vacía el grupo.
copiar_grupo() {
  local r
  [ ${#GRUPO[@]} -gt 0 ] || return 0
  if ! cp -- "${GRUPO[@]}" "$DESTINO${1:+/$1}/"; then
    for r in "${RUTAS_GRUPO[@]}"; do
      fallo_escritura "$r"
    done
  fi
  GRUPO=() RUTAS_GRUPO=()
}

fallo_escritura() {
  printf 'instalar.sh: no pude escribir %s\n' "$1" >&2
  FALLOS=$((FALLOS + 1))
}

# registrar <ruta> <fuente o contenido> <copia|generado>
registrar() {
  printf '%s %s\n' "$ESTADO" "$1"
  case "$ESTADO" in
    crear) N_CREAR=$((N_CREAR + 1)) ;;
    igual) N_IGUAL=$((N_IGUAL + 1)) ;;
    conflicto)
      N_CONFLICTO=$((N_CONFLICTO + 1))
      CONF_RUTAS+=("$1")
      CONF_ORIGEN+=("$2")
      CONF_TIPO+=("$3")
      ;;
  esac
}

procesar_archivos() {
  local r i dst
  N_CREAR=0 N_IGUAL=0 N_CONFLICTO=0 FALLOS=0
  CONF_RUTAS=() CONF_ORIGEN=() CONF_TIPO=() A_COPIAR=()
  for r in "${MANIFIESTO[@]}"; do
    evaluar_copia "$r" "$FUENTE/$r"
    registrar "$r" "$FUENTE/$r" copia
    if [ "$ESTADO" = crear ] && [ "$APLICAR" -eq 1 ]; then
      A_COPIAR+=("$r")
    fi
  done
  copiar_pendientes
  for i in "${!GEN_RUTAS[@]}"; do
    r=${GEN_RUTAS[$i]}
    evaluar_generado "$r" "${GEN_CONTENIDOS[$i]}"
    registrar "$r" "${GEN_CONTENIDOS[$i]}" generado
    if [ "$ESTADO" = crear ] && [ "$APLICAR" -eq 1 ]; then
      dst="$DESTINO/$r"
      { crear_carpeta_de "$dst" && printf '%s' "${GEN_CONTENIDOS[$i]}" > "$dst"; } || fallo_escritura "$r"
    fi
  done
}

# ---------------------------------------------------------------------------
# rama staging
# ---------------------------------------------------------------------------

# rama_staging: solo informa. El instalador no crea, mueve ni borra ramas: en un repo nuevo, staging
# nace en el servidor desde main, después del PR T0 (paso 9 de /crear-repo). No hace fetch: solo ve
# lo que ya hay en el repo local.
rama_staging() {
  if git_destino show-ref --verify --quiet refs/heads/staging; then
    RAMA=existe
  elif git_destino show-ref --verify --quiet refs/remotes/origin/staging; then
    RAMA=existe
    NOTAS+=("staging existe solo como origin/staging: no se creó la rama local; git switch staging la crea desde origin/staging.")
  else
    RAMA='no se crea'
  fi
  printf 'rama staging: %s\n' "$RAMA"
}

# ---------------------------------------------------------------------------
# pasos manuales
# ---------------------------------------------------------------------------

# ruta_config_bot: ruta de la configuración de gh del bot, en la forma C:/Users/... en Git Bash.
ruta_config_bot() {
  local base=${HOME:-}
  if [ -n "$base" ] && [ -d "$base" ]; then
    base=$(cd -- "$base" && { pwd -W 2> /dev/null || pwd; }) || base=$HOME
  fi
  RUTA_CONFIG_BOT="${base:-\$HOME}/.talos-gh"
}

imprimir_conflictos() {
  local i
  [ "$N_CONFLICTO" -gt 0 ] || return 0
  printf '%s\n' '# Conflictos: el instalador no tocó estos archivos. Compáralos con la versión del framework y resuélvelos a mano antes de commitear.'
  for i in "${!CONF_RUTAS[@]}"; do
    citar "$DESTINO/${CONF_RUTAS[$i]}"
    local destino_citado=$CITADO
    if [ "${CONF_TIPO[$i]}" = copia ]; then
      citar "${CONF_ORIGEN[$i]}"
      printf 'diff %s %s\n' "$CITADO" "$destino_citado"
    else
      printf '%s\n' "# ${CONF_RUTAS[$i]} es un archivo generado: el diff lo compara con el contenido que habría escrito el instalador."
      printf "diff - %s <<'GENERADO'\n" "$destino_citado"
      printf '%s' "${CONF_ORIGEN[$i]}"
      case "${CONF_ORIGEN[$i]}" in
        *$'\n' | '') ;;
        *) printf '\n' ;;
      esac
      printf '%s\n' 'GENERADO'
    fi
  done
}

# preparar_pasos: lee la plantilla de los pasos manuales, reemplaza sus marcadores y la parte en
# PASOS_ANTES y PASOS_DESPUES, alrededor de la línea {{conflictos}}: ahí va el bloque de conflictos,
# si los hay. Los valores que pueden traer cualquier carácter (la ruta de gh y la del destino) se
# reemplazan al final, para que un {{...}} dentro de ellos no cambie nada más.
preparar_pasos() {
  local marca='{{conflictos}}'
  ruta_config_bot
  citar "$DESTINO"
  leer_plantilla pasos-manuales.txt
  rellenar "$PLANTILLA" dueno "$DUENO" repo "$REPO" org "$ORG" servicio "$SERVICIO" puerto "$PUERTO" bot "$BOT" \
    gh_config_dir "$RUTA_CONFIG_BOT" destino "$CITADO"
  case "$RELLENO" in
    *"$marca"$'\n'*) ;;
    *) error_fuente "la plantilla instalador/plantillas/pasos-manuales.txt no tiene una línea $marca" ;;
  esac
  PASOS_ANTES=${RELLENO%%"$marca"$'\n'*}
  PASOS_DESPUES=${RELLENO#*"$marca"$'\n'}
}

imprimir_pasos() {
  printf '%s\n' '== Pasos manuales'
  printf '%s' "$PASOS_ANTES"
  imprimir_conflictos
  printf '%s' "$PASOS_DESPUES"
}

# ---------------------------------------------------------------------------
# principal
# ---------------------------------------------------------------------------

main() {
  local nota
  # Nunca pisar un archivo por una redirección.
  set -C
  # Que git trabaje sobre el destino y no sobre un repo heredado del entorno.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR
  NOTAS=()
  analizar_argumentos "$@"
  ubicar_fuente
  validar_destino
  cd -- "$DESTINO" || error_uso "no pude entrar al destino: $DESTINO"
  leer_conf
  [ -f "$DIR_INSTALADOR/manifiesto.txt" ] || error_fuente "falta el manifiesto: $DIR_INSTALADOR/manifiesto.txt"
  leer_manifiesto "$DIR_INSTALADOR/manifiesto.txt"
  validar_manifiesto
  identificar_repo
  [ -n "$SERVICIO" ] || SERVICIO=$REPO
  if [ -n "$MODO_FORZADO" ]; then
    MODO=$MODO_FORZADO
  else
    detectar_modo
    MODO=$MODO_DETECTADO
  fi
  generar
  preparar_pasos

  if [ "$APLICAR" -eq 1 ]; then
    printf '%s\n' 'instalador del framework: aplicando (solo escribe archivos que no existen; no crea ramas)'
  else
    printf '%s\n' 'instalador del framework: simulación, no escribe nada en el destino (para escribir, repite con --aplicar)'
  fi
  printf 'fuente: %s\ndestino: %s\n' "$FUENTE" "$DESTINO"
  printf 'repo: %s/%s, servicio: %s, puerto: %s\n' "$DUENO" "$REPO" "$SERVICIO" "$PUERTO"
  printf 'modo %s\n' "$MODO"
  procesar_archivos
  rama_staging
  for nota in "${NOTAS[@]}"; do
    printf 'nota: %s\n' "$nota"
  done
  # La palabra "conflicto" solo aparece en la salida cuando hay alguno.
  if [ "$N_CONFLICTO" -gt 0 ]; then
    printf 'resumen: %d crear, %d igual, %d conflicto\n' "$N_CREAR" "$N_IGUAL" "$N_CONFLICTO"
  else
    printf 'resumen: %d crear, %d igual\n' "$N_CREAR" "$N_IGUAL"
  fi
  imprimir_pasos

  if [ "$FALLOS" -gt 0 ]; then
    printf 'instalar.sh: %d escrituras fallaron; revisa los permisos del destino\n' "$FALLOS" >&2
    return 1
  fi
  [ "$N_CONFLICTO" -eq 0 ] || return 3
  return 0
}

# Con "source" (pruebas unitarias) solo se cargan las funciones.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
  exit $?
fi
