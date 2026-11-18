output "bucket" {
  description = "Bucket de fotos. Subir a este prefijo para disparar la clasificacion."
  value       = module.almacenamiento.bucket_id
}

output "prefijo_entrada" {
  description = "Prefijo donde hay que subir las fotos."
  value       = var.prefijo_entrada
}

output "tabla" {
  description = "Tabla DynamoDB con las clasificaciones."
  value       = module.catalogo.tabla_name
}

output "funcion" {
  description = "Nombre de la funcion clasificadora."
  value       = module.clasificador.funcion_name
}

output "dlq" {
  description = "URL de la cola de errores."
  value       = module.clasificador.dlq_url
}

output "dashboard_url" {
  description = "Link directo al dashboard de CloudWatch."
  value       = module.observabilidad.dashboard_url
}

output "rol_github_arn" {
  description = "ARN del rol que asume GitHub Actions via OIDC. Va en el secret AWS_ROLE_ARN."
  value       = module.cicd_oidc.rol_arn
}

output "comando_consulta" {
  description = "Consulta de resultados del lote, entregable especifico de PixelPaws."
  value       = "aws dynamodb scan --table-name ${module.catalogo.tabla_name} --projection-expression 'archivo,etiqueta,confianza,fecha' --region ${var.region}"
}
