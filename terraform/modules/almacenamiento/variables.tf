variable "nombre" {
  description = "Prefijo de nombres."
  type        = string
}

variable "sufijo" {
  description = "Sufijo aleatorio para unicidad global del bucket."
  type        = string
}

variable "prefijo_entrada" {
  description = "Prefijo de fotos sin clasificar."
  type        = string
}

variable "prefijo_salida" {
  description = "Prefijo de fotos clasificadas."
  type        = string
}
