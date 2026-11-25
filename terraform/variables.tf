variable "proyecto" {
  description = "Nombre del proyecto. Va en la etiqueta project y como prefijo de todos los nombres de recurso."
  type        = string
  default     = "pixelpaws"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.proyecto))
    error_message = "Solo minusculas, numeros y guiones, entre 3 y 20 caracteres (restriccion de nombres de bucket S3)."
  }
}

variable "equipo" {
  description = "Equipo responsable. Etiqueta team."
  type        = string
}

variable "entorno" {
  description = "Entorno de despliegue. Etiqueta env."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "Solo se admiten los entornos dev y prod."
  }
}

variable "owner" {
  description = "Responsable del despliegue. Etiqueta owner."
  type        = string
}

variable "region" {
  description = "Region unica del despliegue, elegida por menor costo."
  type        = string
  default     = "us-east-2"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-2"], var.region)
    error_message = "El proyecto se despliega en una sola region, de la franja mas barata: us-east-1, us-east-2 o us-west-2."
  }
}

variable "enable_oidc" {
  description = "Crea el proveedor OIDC de GitHub y el rol que asume el pipeline. Es la forma de autenticar sin claves."
  type        = bool
  default     = true
}

variable "repositorio_github" {
  description = "Repositorio habilitado a asumir el rol via OIDC, en formato owner/nombre."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_oidc || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.repositorio_github))
    error_message = "Con enable_oidc en true hay que indicar el repositorio como owner/nombre."
  }
}

variable "monto_presupuesto_usd" {
  description = "Tope mensual del presupuesto en USD. La consigna fija 10."
  type        = number
  default     = 10

  validation {
    condition     = var.monto_presupuesto_usd > 0 && var.monto_presupuesto_usd <= 10
    error_message = "La consigna limita el presupuesto a USD 10."
  }
}

variable "emails_alerta" {
  description = "Direcciones que reciben la alarma y los avisos de presupuesto. Deben ser las de todos los integrantes."
  type        = list(string)

  validation {
    condition     = length(var.emails_alerta) > 0
    error_message = "Hace falta al menos un destinatario, si no la alerta no le llega a nadie."
  }
}
