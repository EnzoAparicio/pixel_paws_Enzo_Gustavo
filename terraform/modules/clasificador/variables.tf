variable "nombre" {
  type        = string
  description = "Prefijo de nombres."
}

variable "region" {
  type        = string
  description = "Region del despliegue."
}

variable "zip_path" {
  type        = string
  description = "Ruta al paquete de despliegue."
}

variable "zip_hash" {
  type        = string
  description = "Hash base64 del paquete, para que Terraform detecte cambios de codigo."
}

variable "memoria_mb" {
  type        = number
  description = "Memoria de la funcion."
}

variable "timeout_seg" {
  type        = number
  description = "Timeout de la funcion."
}

variable "bucket_id" {
  type        = string
  description = "Nombre del bucket de fotos."
}

variable "bucket_arn" {
  type        = string
  description = "ARN del bucket de fotos."
}

variable "tabla_name" {
  type        = string
  description = "Nombre de la tabla de clasificaciones."
}

variable "tabla_arn" {
  type        = string
  description = "ARN de la tabla de clasificaciones."
}

variable "prefijo_entrada" {
  type        = string
  description = "Prefijo que filtra el evento."
}

variable "prefijo_salida" {
  type        = string
  description = "Prefijo de salida."
}

variable "min_confianza" {
  type        = number
  description = "Umbral de confianza de Rekognition."
}

variable "mover_clasificadas" {
  type        = bool
  description = "Activa la copia a clasificadas/<especie>/."
}

variable "retencion_logs_dias" {
  type        = number
  description = "Retencion de logs."
}

variable "crear_iam_propio" {
  type        = bool
  description = "Crea el rol de menor privilegio."
}

variable "rol_ejecucion_externo" {
  type        = string
  description = "Rol preexistente a usar si no se crea uno propio."
}
