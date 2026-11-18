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
