variable "nombre" {
  type        = string
  description = "Prefijo de nombres."
}

variable "region" {
  type        = string
  description = "Region del despliegue."
}

variable "funcion_name" {
  type        = string
  description = "Funcion a monitorear."
}

variable "dlq_name" {
  type        = string
  description = "Cola de errores a monitorear."
}

variable "tabla_name" {
  type        = string
  description = "Tabla a graficar."
}

variable "emails_alerta" {
  type        = list(string)
  description = "Destinatarios de las alarmas."
}
