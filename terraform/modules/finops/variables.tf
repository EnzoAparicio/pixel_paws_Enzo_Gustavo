variable "nombre" {
  type        = string
  description = "Prefijo de nombres."
}

variable "proyecto" {
  type        = string
  description = "Valor de la etiqueta project, usado para filtrar el costo."
}

variable "enable_budget" {
  type        = bool
  description = "Crea el presupuesto. Requiere acceso a facturacion."
}

variable "monto_usd" {
  type        = number
  description = "Tope mensual en USD."
}

variable "emails_alerta" {
  type        = list(string)
  description = "Destinatarios de los avisos."
}
