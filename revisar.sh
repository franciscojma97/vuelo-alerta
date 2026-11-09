#!/bin/bash
# Versión en la nube (GitHub Actions): revisa en Google Vuelos el precio más barato en vuelo DIRECTO
# de cada ruta y manda aviso al iPhone (ntfy) si baja respecto a la revisión anterior.
DIR="$(cd "$(dirname "$0")" && pwd)/estado"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
LOG="$DIR/historial.log"
export TZ=America/Monterrey
NOW=$(date "+%Y-%m-%d %H:%M")
HOY=$(date +%Y%m%d)

url() { # origen destino ida vuelta
  echo "https://www.google.com/travel/flights?q=Flights%20from%20$1%20to%20$2%20on%20$3%20through%20$4&hl=es&curr=MXN&gl=mx"
}

# Imprime "precio aerolínea" del directo más barato (si se da hora de salida, solo ese vuelo)
directo_mas_barato() { # origen destino ida vuelta [hora]
  local hora=${5:-[0-9:]+}
  curl -s --max-time 60 -A "$UA" -H "Accept-Language: es-MX" "$(url $1 $2 $3 $4)" \
    | grep -oE "A partir de [0-9]+ pesos mexicanos[^\"]{0,200}Vuelo directo de [^.]+\. Sale [^.]+ a las $hora\. Llega" \
    | sed -E 's/A partir de ([0-9]+) pesos mexicanos.*Vuelo directo de ([^.]+)\. Sale.*/\1 \2/' \
    | sort -n | head -1
}

# ruta: id  nombre  origen  destino  "idas"  "vueltas"  último día (AAAAMMDD)  [hora de salida]  [avisar solo debajo de este precio]
revisar_ruta() {
  local id=$1 nombre=$2 o=$3 d=$4 limite=$7 hora=$8 umbral=$9
  local -a idas=($5) vueltas=($6)
  [[ $HOY -gt $limite ]] && return
  local mejor="" mejor_aero="" mejor_ida="" mejor_vuelta="" r p a i v
  for i in "${idas[@]}"; do for v in "${vueltas[@]}"; do
    r=$(directo_mas_barato $o $d $i $v $hora); sleep 2
    # A veces Google responde sin resultados; se reintenta una vez
    [[ -z "$r" ]] && { sleep 10; r=$(directo_mas_barato $o $d $i $v $hora); }
    [[ -z "$r" ]] && continue
    p=${r%% *}; a=${r#* }
    if [[ -z "$mejor" || $p -lt $mejor ]]; then mejor=$p mejor_aero=$a mejor_ida=$i mejor_vuelta=$v; fi
  done; done
  if [[ -z "$mejor" ]]; then
    echo "$NOW  [$nombre] ERROR: no se encontró precio directo" >> "$LOG"; return
  fi
  local fechas="ida ${mejor_ida:8:2}/${mejor_ida:5:2}, vuelta ${mejor_vuelta:8:2}/${mejor_vuelta:5:2}"
  local anterior=$(cat "$DIR/ultimo_precio_$id" 2>/dev/null)
  echo "$NOW  [$nombre] $mejor MXN ($mejor_aero, $fechas)" >> "$LOG"
  echo "$mejor" > "$DIR/ultimo_precio_$id"
  if [[ -n "$anterior" && $mejor -lt $anterior && ( -z "$umbral" || $mejor -lt $umbral ) ]]; then
    local msg="¡Bajó \$$((anterior - mejor))! Ahora $mejor MXN (antes $anterior) ida y vuelta DIRECTO $nombre. $mejor_aero, $fechas"
    echo "$NOW  ALERTA: $msg" >> "$LOG"
    curl -s --max-time 30 -H "Title: Bajo el vuelo" -H "Tags: airplane" -H "Priority: high" \
      -H "Click: $(url $o $d $mejor_ida $mejor_vuelta)" -d "$msg" "https://ntfy.sh/$NTFY_TEMA" > /dev/null
  fi
}

# Madrid tiene ~110 combinaciones de fechas: en cada corrida se revisa 1 de 8 grupos (todas cada ~2 horas).
# madrid.tsv guarda el último precio de cada combinación: ida vuelta precio aerolínea
revisar_madrid() {
  local tabla="$DIR/madrid.tsv" nombre="MTY→Madrid" grupos=8
  [[ $HOY -gt 20270317 ]] && return
  local grupo=${GRUPO_MADRID:-$(( $(date +%s) / 900 % grupos ))}
  touch "$tabla"
  local antes=$(sort -k3,3n "$tabla" | head -1)
  local n=0 k i v r
  while read -r i v; do
    k=$(( n++ % grupos )); [[ $MADRID_TODO == 1 || $k == $grupo ]] || continue
    [[ ${i//-/} -lt $HOY ]] && { sed -i.bak "/^$i $v /d" "$tabla"; continue; }
    r=$(directo_mas_barato MTY MAD $i $v); sleep 2
    [[ -z "$r" ]] && { sleep 10; r=$(directo_mas_barato MTY MAD $i $v); sleep 2; }
    sed -i.bak "/^$i $v /d" "$tabla"
    [[ -n "$r" ]] && echo "$i $v $r" >> "$tabla"
  done < <(python3 "$(dirname "$DIR")/fechas_madrid.py")
  rm -f "$tabla.bak"
  if [[ $MADRID_TODO == 1 ]]; then seq 0 $((grupos - 1)) >> "$DIR/madrid_grupos"; else echo $grupo >> "$DIR/madrid_grupos"; fi
  local mejor=$(sort -k3,3n "$tabla" | head -1)
  [[ -z "$mejor" ]] && { echo "$NOW  [$nombre] ERROR: no se encontró precio directo" >> "$LOG"; return; }
  read -r i v p a <<< "$mejor"
  local fechas="ida ${i:8:2}/${i:5:2}, vuelta ${v:8:2}/${v:5:2}, $(( ( $(date -d $v +%s) - $(date -d $i +%s) ) / 86400 )) días"
  echo "$NOW  [$nombre] $p MXN ($a, $fechas)" >> "$LOG"
  local pa=$(awk '{print $3}' <<< "$antes")
  # No avisar hasta tener la primera vuelta completa de los 8 grupos
  if [[ $(sort -u "$DIR/madrid_grupos" | wc -l) -ge $grupos && -n "$pa" && $p -lt $pa ]]; then
    local msg="¡Bajó \$$((pa - p))! Ahora $p MXN (antes $pa) ida y vuelta DIRECTO $nombre. $a, $fechas"
    echo "$NOW  ALERTA: $msg" >> "$LOG"
    curl -s --max-time 30 -H "Title: Bajo el vuelo" -H "Tags: airplane" -H "Priority: high" \
      -H "Click: $(url MTY MAD $i $v)" -d "$msg" "https://ntfy.sh/$NTFY_TEMA" > /dev/null
  fi
}

revisar_ruta cabos "MTY→Los Cabos (sale 6:33)" MTY SJD "2026-12-10" "2026-12-15" 20261210 6:33 4000
revisar_ruta vsa "MTY→Villahermosa" MTY VSA "2027-01-19" "2027-01-29" 20270119
revisar_madrid
