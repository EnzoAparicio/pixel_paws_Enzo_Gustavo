terraform {
  # Versiones ancladas, exigido por la consigna 2.3.
  # 1.10 es el minimo para use_lockfile (bloqueo nativo del backend S3).
  required_version = "~> 1.17"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Configuracion parcial: el resto vive en backend.hcl, que no se versiona
  # con valores reales porque el nombre del bucket es unico por equipo.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  # Etiquetas obligatorias de la consigna 2.3, aplicadas a todo recurso que
  # las soporte. Asi no hay que repetirlas modulo por modulo.
  default_tags {
    tags = {
      project = var.proyecto
      team    = var.equipo
      env     = var.entorno
      owner   = var.owner
    }
  }
}
