#!/usr/bin/env bash
# Punto unico de entrada: lo usan la persona en su terminal y el pipeline.
# Mismo patron que el lab 06, para que lo que funciona local funcione en CI.
# Uso: ./scripts/tf.sh plan|apply|destroy
set -euo pipefail

ACTION="${1:?Uso: tf.sh plan|apply|destroy}"
TF="${TF_BIN:-terraform}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "${ROOT}/terraform"
echo ">> ${TF} ${ACTION}"

"${TF}" fmt -check -recursive
"${TF}" init -input=false -backend-config=backend.hcl
"${TF}" validate

case "${ACTION}" in
  plan)
    "${TF}" plan -input=false
    ;;
  apply)
    "${TF}" plan -input=false -out=tfplan
    "${TF}" apply -input=false tfplan
    ;;
  destroy)
    "${TF}" destroy -input=false -auto-approve
    ;;
  *)
    echo "Accion desconocida: ${ACTION}" >&2
    exit 1
    ;;
esac
