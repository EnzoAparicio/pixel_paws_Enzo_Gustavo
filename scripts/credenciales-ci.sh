#!/usr/bin/env bash
# Genera credenciales temporales del rol pixelpaws-ci para GitHub (12 h desde un usuario IAM).
set -euo pipefail

HORAS="${1:-12}"
CUENTA="$(aws sts get-caller-identity --query Account --output text)"
ROL="arn:aws:iam::${CUENTA}:role/pixelpaws-ci"
SESION="github-$(date +%Y%m%d-%H%M)"

asumir() {
  aws sts assume-role --role-arn "$ROL" --role-session-name "$SESION" \
    --duration-seconds "$1" \
    --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken,Expiration]" \
    --output text
}

if ! SALIDA="$(asumir $((HORAS * 3600)) 2>/dev/null)"; then
  echo "AWS no permite ${HORAS} h desde esta identidad (encadenamiento de roles). Pido 1 h." >&2
  SALIDA="$(asumir 3600)"
fi
read -r AK SK ST VENCE <<< "$SALIDA"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh secret set AWS_ACCESS_KEY_ID --body "$AK"
  gh secret set AWS_SECRET_ACCESS_KEY --body "$SK"
  gh secret set AWS_SESSION_TOKEN --body "$ST"
  echo "Secrets cargados en GitHub. Vencen: ${VENCE}"
else
  echo "Carga estos tres secrets en GitHub (Settings > Secrets and variables > Actions)."
  echo "Vencen: ${VENCE}. No los pegues en ningun otro lado."
  echo ""
  echo "AWS_ACCESS_KEY_ID=${AK}"
  echo "AWS_SECRET_ACCESS_KEY=${SK}"
  echo "AWS_SESSION_TOKEN=${ST}"
fi
