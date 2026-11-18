#!/usr/bin/env bash
# Genera credenciales TEMPORALES para el pipeline asumiendo el rol pixelpaws-ci.
#
# Por que existe: la organizacion que administra la cuenta bloquea los
# proveedores OIDC, asi que GitHub Actions no puede usar identidad federada.
# En su lugar recibe credenciales que caducan solas, nunca claves permanentes.
#
# Duracion: desde un usuario IAM, hasta 12 h. Desde un rol asumido (la sesion
# federada de la consola), AWS limita el encadenamiento de roles a 1 h.
#
# Uso: bash scripts/credenciales-ci.sh [horas]
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
