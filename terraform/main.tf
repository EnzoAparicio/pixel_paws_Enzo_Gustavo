locals {
  nombre = "${var.proyecto}-${var.entorno}"
}

# Sufijo aleatorio: el nombre de bucket es unico a nivel global.
resource "random_id" "sufijo" {
  byte_length = 3
}

data "archive_file" "clasificador" {
  type        = "zip"
  source_file = "${path.module}/../lambda/clasificador.py"
  output_path = "${path.module}/.build/clasificador.zip"
}

module "almacenamiento" {
  source = "./modules/almacenamiento"

  nombre = local.nombre
  sufijo = random_id.sufijo.hex
}

module "catalogo" {
  source = "./modules/catalogo"

  nombre = local.nombre
}

module "clasificador" {
  source = "./modules/clasificador"

  nombre   = local.nombre
  region   = var.region
  zip_path = data.archive_file.clasificador.output_path
  zip_hash = data.archive_file.clasificador.output_base64sha256

  bucket_id  = module.almacenamiento.bucket_id
  bucket_arn = module.almacenamiento.bucket_arn
  tabla_name = module.catalogo.tabla_name
  tabla_arn  = module.catalogo.tabla_arn
}

module "observabilidad" {
  source = "./modules/observabilidad"

  nombre        = local.nombre
  region        = var.region
  funcion_name  = module.clasificador.funcion_name
  dlq_name      = module.clasificador.dlq_name
  tabla_name    = module.catalogo.tabla_name
  emails_alerta = var.emails_alerta
}

module "finops" {
  source = "./modules/finops"

  nombre        = local.nombre
  proyecto      = var.proyecto
  monto_usd     = var.monto_presupuesto_usd
  emails_alerta = var.emails_alerta
}

module "cicd_oidc" {
  source = "./modules/cicd_oidc"

  nombre      = local.nombre
  enable_oidc = var.enable_oidc
  repositorio = var.repositorio_github
}
