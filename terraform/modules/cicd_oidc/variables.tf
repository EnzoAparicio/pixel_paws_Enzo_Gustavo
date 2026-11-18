variable "nombre" {
  type        = string
  description = "Prefijo de nombres."
}

variable "enable_oidc" {
  type        = bool
  description = "Crea el proveedor OIDC y el rol. Requiere permisos de IAM."
}

variable "repositorio" {
  type        = string
  description = "Repositorio habilitado, en formato owner/nombre."
}
