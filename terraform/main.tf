locals {
  nombre = "${var.proyecto}-${var.entorno}"
}

# Sufijo aleatorio: el nombre de bucket es unico a nivel global.
resource "random_id" "sufijo" {
  byte_length = 3
}

# El paquete se arma en la raiz y se pasa al modulo, asi el modulo no necesita
# conocer rutas relativas fuera de si mismo.
data "archive_file" "clasificador" {
  type        = "zip"
  source_file = "${path.module}/../lambda/clasificador.py"
  output_path = "${path.module}/.build/clasificador.zip"
}

module "almacenamiento" {
  source = "./modules/almacenamiento"

  nombre          = local.nombre
  sufijo          = random_id.sufijo.hex
  prefijo_entrada = var.prefijo_entrada
  prefijo_salida  = var.prefijo_salida
}

module "catalogo" {
  source = "./modules/catalogo"

  nombre = local.nombre
}

module "clasificador" {
  source = "./modules/clasificador"

  nombre      = local.nombre
  region      = var.region
  zip_path    = data.archive_file.clasificador.output_path
  zip_hash    = data.archive_file.clasificador.output_base64sha256
  memoria_mb  = var.memoria_mb
  timeout_seg = var.timeout_seg

  bucket_id  = module.almacenamiento.bucket_id
  bucket_arn = module.almacenamiento.bucket_arn
  tabla_name = module.catalogo.tabla_name
  tabla_arn  = module.catalogo.tabla_arn

  prefijo_entrada     = var.prefijo_entrada
  prefijo_salida      = var.prefijo_salida
  min_confianza       = var.min_confianza
  mover_clasificadas  = var.mover_clasificadas
  retencion_logs_dias = var.retencion_logs_dias

  crear_iam_propio      = var.crear_iam_propio
  rol_ejecucion_externo = var.rol_ejecucion_externo
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
  enable_budget = var.enable_budget
  monto_usd     = var.monto_presupuesto_usd
  emails_alerta = var.emails_alerta
}

module "cicd_oidc" {
  source = "./modules/cicd_oidc"

  nombre      = local.nombre
  enable_oidc = var.enable_oidc
  repositorio = var.repositorio_github
}
