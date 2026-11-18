#!/usr/bin/env bash
# Prueba de humo de punta a punta: sube una foto, espera y verifica que la
# clasificacion quedo en DynamoDB. Es la prueba que corre el pipeline tras el
# apply y la que se muestra en la demo.
set -euo pipefail

FOTO="${1:?Uso: smoke-test.sh <ruta-a-foto>}"
[ -f "$FOTO" ] || { echo "ERROR: no existe la foto ${FOTO}" >&2; exit 1; }
# Ruta absoluta ANTES del cd: si no, una ruta relativa deja de existir.
FOTO="$(cd "$(dirname "$FOTO")" && pwd)/$(basename "$FOTO")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}/terraform"

BUCKET="$(terraform output -raw bucket)"
TABLA="$(terraform output -raw tabla)"
PREFIJO="$(terraform output -raw prefijo_entrada)"
CLAVE="${PREFIJO}smoke-$(date +%s).jpg"

echo ">> Subiendo ${CLAVE} a ${BUCKET}"
aws s3 cp "$FOTO" "s3://${BUCKET}/${CLAVE}"

echo ">> Esperando la clasificacion (hasta 60 s)"
for i in $(seq 1 12); do
  if aws dynamodb get-item --table-name "$TABLA" \
      --key "{\"archivo\":{\"S\":\"${CLAVE}\"}}" \
      --query 'Item.etiqueta.S' --output text 2>/dev/null | grep -qv '^None$'; then
    echo ""
    echo ">> Clasificada:"
    aws dynamodb get-item --table-name "$TABLA" \
      --key "{\"archivo\":{\"S\":\"${CLAVE}\"}}" \
      --query 'Item.{archivo:archivo.S,etiqueta:etiqueta.S,confianza:confianza.N,fecha:fecha.S}'
    exit 0
  fi
  sleep 5
done

echo "ERROR: la foto no se clasifico en 60 segundos." >&2
echo "Revisar los logs: aws logs tail /aws/lambda/\$(terraform output -raw funcion) --since 5m" >&2
exit 1
