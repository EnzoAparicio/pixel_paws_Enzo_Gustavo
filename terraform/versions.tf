terraform {
  # Versiones ancladas (consigna 2.3); 1.10 es el minimo para use_lockfile.
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

  # Backend parcial: el bucket y la clave estan en backend.hcl.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  # Etiquetas obligatorias (consigna 2.3) en todo recurso, sin repetirlas por modulo.
  default_tags {
    tags = {
      project = var.proyecto
      team    = var.equipo
      env     = var.entorno
      owner   = var.owner
    }
  }
}
