#!/usr/bin/env bash
# Lote de prueba de PixelPaws: sube todas las fotos de pruebas/lote/ al prefijo
# de entrada del bucket, espera a que la Lambda las clasifique y muestra una
# tabla con los resultados leidos de DynamoDB. Es el entregable especifico
# "lote de 20 fotos clasificado y consulta de resultados".
#
# No llama a terraform: el bucket y la tabla entran por argumento o variable
# de entorno (en CloudShell, salen de terraform output):
#
#   export BUCKET="$(terraform output -raw bucket)"
#   export TABLA="$(terraform output -raw tabla)"
#   bash scripts/lote.sh
#
# Uso: lote.sh [-b bucket] [-t tabla] [-p prefijo] [-r region] [-d carpeta]
#              [-e espera_seg] [-c]
#   -b  bucket de fotos             (o BUCKET)
#   -t  tabla DynamoDB              (o TABLA)
#   -p  prefijo de entrada          (o PREFIJO, por defecto uploads/)
#   -r  region                      (o AWS_REGION, por defecto us-east-2)
#   -d  carpeta con las fotos       (o LOTE_DIR, por defecto pruebas/lote)
#   -e  espera maxima en segundos   (o ESPERA, por defecto 180)
#   -c  solo consulta: no sube nada, muestra lo que ya esta en la tabla
#
# Las fotos se suben a <prefijo>lote/<nombre>. Si el lote se corre dos veces,
# la Lambda detecta que el archivo ya esta en la tabla y no vuelve a pagar
# Rekognition (deduplicacion de clasificador.py).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

BUCKET="${BUCKET:-}"
TABLA="${TABLA:-}"
PREFIJO="${PREFIJO:-uploads/}"
REGION="${AWS_REGION:-us-east-2}"
LOTE_DIR="${LOTE_DIR:-${ROOT}/pruebas/lote}"
ESPERA="${ESPERA:-180}"
SOLO_CONSULTA=false
INTERVALO="${INTERVALO:-5}"
# Rekognition acepta hasta 15 MB desde S3; el limite del equipo es 5 MB.
MAX_BYTES=$((5 * 1024 * 1024))

uso() {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":b:t:p:r:d:e:ch" opt; do
  case "$opt" in
    b) BUCKET="$OPTARG" ;;
    t) TABLA="$OPTARG" ;;
    p) PREFIJO="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    d) LOTE_DIR="$OPTARG" ;;
    e) ESPERA="$OPTARG" ;;
    c) SOLO_CONSULTA=true ;;
    h) uso 0 ;;
    :) echo "ERROR: -${OPTARG} necesita un valor." >&2; uso 1 ;;
    *) echo "ERROR: opcion desconocida -${OPTARG}." >&2; uso 1 ;;
  esac
done

# --- Validaciones ---------------------------------------------------------

command -v aws >/dev/null || { echo "ERROR: falta la CLI de AWS (aws)." >&2; exit 1; }

if [[ -z "$BUCKET" || -z "$TABLA" ]]; then
  echo "ERROR: faltan el bucket y/o la tabla." >&2
  echo "En CloudShell, desde terraform/:" >&2
  echo '  export BUCKET="$(terraform output -raw bucket)"' >&2
  echo '  export TABLA="$(terraform output -raw tabla)"' >&2
  exit 1
fi

[[ "$PREFIJO" == */ ]] || PREFIJO="${PREFIJO}/"
[[ "$ESPERA" =~ ^[0-9]+$ ]] || { echo "ERROR: la espera tiene que ser un numero de segundos." >&2; exit 1; }
[[ -d "$LOTE_DIR" ]] || { echo "ERROR: no existe la carpeta ${LOTE_DIR}." >&2; exit 1; }

# Fotos del lote: jpg, jpeg y png, sin importar mayusculas. Se ignora LEEME.md.
FOTOS=()
while IFS= read -r -d '' f; do
  FOTOS+=("$f")
done < <(find "$LOTE_DIR" -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0 | sort -z)

if [[ ${#FOTOS[@]} -eq 0 ]]; then
  echo "ERROR: no hay fotos (jpg, jpeg o png) en ${LOTE_DIR}." >&2
  exit 1
fi

# El nombre en S3 se normaliza a [A-Za-z0-9._-]: evita problemas de URL
# encoding en el evento y de escapes en el JSON de la consulta.
clave_de() {
  local nombre
  nombre="$(basename "$1")"
  printf '%s%s' "${PREFIJO}lote/" "$(printf '%s' "$nombre" | sed 's/[^A-Za-z0-9._-]/_/g')"
}

CLAVES=()
for f in "${FOTOS[@]}"; do
  bytes=$(wc -c < "$f" | tr -d ' ')
  if (( bytes > MAX_BYTES )); then
    echo "ERROR: $(basename "$f") pesa ${bytes} bytes, el maximo es 5 MB." >&2
    exit 1
  fi
  CLAVES+=("$(clave_de "$f")")
done

# Dos fotos que normalizan al mismo nombre se pisarian en S3 y en la tabla.
duplicadas="$(printf '%s\n' "${CLAVES[@]}" | sort | uniq -d)"
if [[ -n "$duplicadas" ]]; then
  echo "ERROR: estas fotos quedan con el mismo nombre en S3, renombralas:" >&2
  echo "$duplicadas" >&2
  exit 1
fi

echo ">> Bucket: ${BUCKET} | Tabla: ${TABLA} | Region: ${REGION}"
echo ">> ${#FOTOS[@]} fotos en ${LOTE_DIR}"
if (( ${#FOTOS[@]} != 20 )); then
  echo "AVISO: el entregable pide 20 fotos y hay ${#FOTOS[@]}." >&2
fi

# --- Subida ---------------------------------------------------------------

if [[ "$SOLO_CONSULTA" == false ]]; then
  echo ">> Subiendo a s3://${BUCKET}/${PREFIJO}lote/"
  for i in "${!FOTOS[@]}"; do
    aws s3 cp "${FOTOS[$i]}" "s3://${BUCKET}/${CLAVES[$i]}" \
      --region "$REGION" --only-show-errors
    echo "   $((i + 1))/${#FOTOS[@]} ${CLAVES[$i]}"
  done
fi

# --- Consulta -------------------------------------------------------------

# Consulta de a hasta 100 claves con batch-get-item (el maximo de la API).
# Imprime una linea por item encontrado: archivo, etiqueta, confianza y
# fecha separados por tabs. Las claves que la API deja en
# UnprocessedKeys simplemente siguen pendientes y se piden en la vuelta
# siguiente.
consultar() {
  local claves=("$@") desde json item
  for ((desde = 0; desde < ${#claves[@]}; desde += 100)); do
    json='{"'"$TABLA"'":{"Keys":['
    for item in "${claves[@]:desde:100}"; do
      json+='{"archivo":{"S":"'"$item"'"}},'
    done
    json="${json%,}"'],"ProjectionExpression":"#a,#e,#c,#f","ExpressionAttributeNames":{"#a":"archivo","#e":"etiqueta","#c":"confianza","#f":"fecha"}}}'
    aws dynamodb batch-get-item --region "$REGION" \
      --request-items "$json" \
      --query 'Responses.*[] | [].[archivo.S, etiqueta.S, confianza.N, fecha.S]' \
      --output text
  done
}

declare -A RESULTADO=()
PENDIENTES=("${CLAVES[@]}")
inicio=$SECONDS

if [[ "$SOLO_CONSULTA" == false ]]; then
  echo ">> Esperando la clasificacion (hasta ${ESPERA} s)"
fi

while :; do
  # Se captura primero para que un error de la CLI corte el script (set -e)
  # en vez de perderse dentro de una sustitucion de proceso.
  salida="$(consultar "${PENDIENTES[@]}")"
  while IFS=$'\t' read -r archivo etiqueta confianza fecha; do
    [[ -n "$archivo" && "$archivo" != "None" ]] || continue
    RESULTADO["$archivo"]="${etiqueta}"$'\t'"${confianza}"$'\t'"${fecha}"
  done <<< "$salida"

  restantes=()
  for c in "${PENDIENTES[@]}"; do
    [[ -n "${RESULTADO[$c]+x}" ]] || restantes+=("$c")
  done
  PENDIENTES=("${restantes[@]+"${restantes[@]}"}")

  transcurrido=$((SECONDS - inicio))
  if [[ ${#PENDIENTES[@]} -eq 0 || "$SOLO_CONSULTA" == true ]] || (( transcurrido >= ESPERA )); then
    break
  fi
  echo "   ${#RESULTADO[@]}/${#CLAVES[@]} clasificadas (${transcurrido} s)"
  sleep "$INTERVALO"
done

# --- Tabla final ----------------------------------------------------------

echo ""
{
  printf 'ARCHIVO\tETIQUETA\tCONFIANZA\tFECHA\n'
  for c in "${CLAVES[@]}"; do
    if [[ -n "${RESULTADO[$c]+x}" ]]; then
      printf '%s\t%s\n' "${c#"${PREFIJO}"}" "${RESULTADO[$c]}"
    else
      printf '%s\t%s\t%s\t%s\n' "${c#"${PREFIJO}"}" "PENDIENTE" "-" "-"
    fi
  done
} | column -t -s $'\t'

perros=0 gatos=0 otras=0
for c in "${!RESULTADO[@]}"; do
  case "$(cut -f1 <<< "${RESULTADO[$c]}")" in
    Dog) perros=$((perros + 1)) ;;
    Cat) gatos=$((gatos + 1)) ;;
    *) otras=$((otras + 1)) ;;
  esac
done

echo ""
echo ">> Resumen: ${perros} perros, ${gatos} gatos, ${otras} sin clasificar, ${#PENDIENTES[@]} pendientes."

if [[ ${#PENDIENTES[@]} -gt 0 ]]; then
  echo "ERROR: ${#PENDIENTES[@]} fotos no aparecieron en la tabla." >&2
  echo "Revisar los logs: aws logs tail /aws/lambda/\$(terraform output -raw funcion) --since 10m --region ${REGION}" >&2
  echo "Y la DLQ: aws sqs get-queue-attributes --queue-url \$(terraform output -raw dlq) --attribute-names ApproximateNumberOfMessages --region ${REGION}" >&2
  exit 1
fi
