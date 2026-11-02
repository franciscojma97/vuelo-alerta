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

# ruta: id  nombre  origen  destino  "idas"  "vueltas"  último día (AAAAMMDD)  [hora de salida]
revisar_ruta() {
  local id=$1 nombre=$2 o=$3 d=$4 limite=$7 hora=$8
  local -a idas=($5) vueltas=($6)
  [[ $HOY -gt $limite ]] && return
  local mejor="" mejor_aero="" mejor_ida="" mejor_vuelta="" r p a i v
  for i in "${idas[@]}"; do for v in "${vueltas[@]}"; do
    r=$(directo_mas_barato $o $d $i $v $hora); sleep 2
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
  if [[ -n "$anterior" && $mejor -lt $anterior ]]; then
    local msg="¡Bajó \$$((anterior - mejor))! Ahora $mejor MXN (antes $anterior) ida y vuelta DIRECTO $nombre. $mejor_aero, $fechas"
    echo "$NOW  ALERTA: $msg" >> "$LOG"
    curl -s --max-time 30 -H "Title: Bajo el vuelo" -H "Tags: airplane" -H "Priority: high" \
      -H "Click: $(url $o $d $mejor_ida $mejor_vuelta)" -d "$msg" "https://ntfy.sh/$NTFY_TEMA" > /dev/null
  fi
}

revisar_ruta cabos "MTY→Los Cabos (sale 6:33)" MTY SJD "2026-12-10" "2026-12-15" 20261210 6:33
revisar_ruta vsa "MTY→Villahermosa" MTY VSA "2027-01-19" "2027-01-29" 20270119
