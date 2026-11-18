# ---------------------------------------------------------------- identidad
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
  description = "Region unica del despliegue, elegida por menor costo. us-east-2 (Ohio) tiene la misma tarifa que us-east-1 y mejor huella de carbono publicada."
  type        = string
  default     = "us-east-2"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-2"], var.region)
    error_message = "El proyecto se despliega en una sola region, de la franja mas barata: us-east-1, us-east-2 o us-west-2."
  }
}

# ---------------------------------------------------------------- clasificador
variable "prefijo_entrada" {
  description = "Prefijo del bucket donde se suben las fotos sin clasificar. El filtro del evento se acota a este prefijo."
  type        = string
  default     = "uploads/"

  validation {
    condition     = endswith(var.prefijo_entrada, "/")
    error_message = "El prefijo debe terminar en barra."
  }
}

variable "prefijo_salida" {
  description = "Prefijo del bucket donde se copian las fotos ya clasificadas."
  type        = string
  default     = "clasificadas/"

  validation {
    condition     = endswith(var.prefijo_salida, "/")
    error_message = "El prefijo debe terminar en barra."
  }
}

variable "min_confianza" {
  description = "Confianza minima que Rekognition debe tener para devolver una etiqueta."
  type        = number
  default     = 70

  validation {
    condition     = var.min_confianza >= 50 && var.min_confianza <= 99
    error_message = "Debe estar entre 50 y 99. Por debajo de 50 el ruido es inservible."
  }
}

variable "memoria_mb" {
  description = "Memoria de la funcion. 256 MB y no 128 porque Rekognition agrega latencia de red y el default se queda corto."
  type        = number
  default     = 256

  validation {
    condition     = var.memoria_mb >= 128 && var.memoria_mb <= 1024
    error_message = "Entre 128 y 1024 MB. Mas que eso no aporta y encarece."
  }
}

variable "timeout_seg" {
  description = "Timeout de la funcion en segundos."
  type        = number
  default     = 30

  validation {
    condition     = var.timeout_seg >= 10 && var.timeout_seg <= 120
    error_message = "Entre 10 y 120 segundos."
  }
}

variable "retencion_logs_dias" {
  description = "Retencion de los logs en CloudWatch. La consigna exige 7 dias."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14], var.retencion_logs_dias)
    error_message = "El proyecto se limita a retenciones cortas para no generar costo de logs."
  }
}

# ---------------------------------------------------------------- banderas
variable "crear_iam_propio" {
  description = "Crea el rol de ejecucion con politicas de menor privilegio. En AWS Academy Learner Lab va en false porque IAM no permite crear roles. En cuenta propia va en true."
  type        = bool
  default     = true
}

variable "rol_ejecucion_externo" {
  description = "ARN de un rol preexistente a usar cuando crear_iam_propio es false (LabRole en Learner Lab)."
  type        = string
  default     = ""

  validation {
    condition     = var.crear_iam_propio || can(regex("^arn:aws:iam::[0-9]{12}:role/", var.rol_ejecucion_externo))
    error_message = "Con crear_iam_propio en false hay que pasar el ARN de un rol existente."
  }
}

variable "enable_oidc" {
  description = "Crea el proveedor OIDC de GitHub y el rol que asume el pipeline. Requiere permisos de IAM."
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

variable "enable_budget" {
  description = "Crea el presupuesto con avisos. Requiere acceso a facturacion, que Learner Lab no tiene."
  type        = bool
  default     = true
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

variable "mover_clasificadas" {
  description = "Extra de la consigna: copiar las fotos clasificadas a clasificadas/perros y clasificadas/gatos."
  type        = bool
  default     = false
}

variable "emails_alerta" {
  description = "Direcciones que reciben las alarmas y los avisos de presupuesto. Deben ser las de todos los integrantes."
  type        = list(string)

  validation {
    condition     = length(var.emails_alerta) > 0
    error_message = "Hace falta al menos un destinatario, si no la alerta no le llega a nadie."
  }
}
