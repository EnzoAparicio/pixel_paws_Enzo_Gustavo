# Bucket creado por bootstrap.sh; se versiona porque el pipeline lo necesita para el init.
bucket = "tfstate-pixelpaws-10385"
key    = "pixelpaws/dev/terraform.tfstate"
region = "us-east-2"

# Bloqueo nativo del estado en S3 (Terraform 1.10 o posterior), sin tabla DynamoDB.
use_lockfile = true
