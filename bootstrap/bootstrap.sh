#!/usr/bin/env bash
# Crea, una sola vez, el bucket del estado y el rol del pipeline (bootstrap).
set -euo pipefail

REGION="${REGION:-us-east-2}"
SUFIJO="${1:-$RANDOM}"
BUCKET="tfstate-pixelpaws-${SUFIJO}"

echo ">> Creando ${BUCKET} en ${REGION}"
# Fuera de us-east-1, S3 exige LocationConstraint; en us-east-1 lo rechaza.
if [ "$REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"     --create-bucket-configuration LocationConstraint="$REGION"
fi

echo ">> Versionado (permite recuperar un estado corrupto)"
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

echo ">> Cifrado en reposo"
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo ">> Bloqueo de acceso publico"
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo ">> Rol de respaldo del pipeline (el pipeline normal entra por OIDC)"
CUENTA="$(aws sts get-caller-identity --query Account --output text)"
if aws iam get-role --role-name pixelpaws-ci >/dev/null 2>&1; then
  echo "   pixelpaws-ci ya existe, no se toca"
else
  aws iam create-role --role-name pixelpaws-ci     --description "Asumido para generar credenciales temporales del pipeline"     --max-session-duration 43200     --tags Key=project,Value=pixelpaws Key=team,Value=aparicio-gonzalez Key=env,Value=dev Key=owner,Value=enzo-aparicio     --assume-role-policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::${CUENTA}:root\"},\"Action\":\"sts:AssumeRole\"}]}"     >/dev/null
  # El pipeline crea roles, politicas y el presupuesto: necesita IAM.
  aws iam attach-role-policy --role-name pixelpaws-ci     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
  echo "   pixelpaws-ci creado (sesiones de hasta 12 h)"
fi

echo ""
echo "Listo. Pone esto en terraform/backend.hcl:"
echo "  bucket = \"${BUCKET}\""
