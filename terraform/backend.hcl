# Completar con el bucket creado por bootstrap/bootstrap.sh.
# Se versiona con el valor real: el pipeline lo necesita para el init. El nombre
# de un bucket no es un secreto.
bucket = "tfstate-pixelpaws-31497"
key    = "pixelpaws/dev/terraform.tfstate"
region = "us-east-2"

# Bloqueo nativo del backend S3, disponible desde Terraform 1.10.
# No hace falta tabla DynamoDB de locks.
use_lockfile = true
