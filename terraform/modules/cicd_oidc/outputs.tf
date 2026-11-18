output "rol_arn" {
  value = var.enable_oidc ? aws_iam_role.github[0].arn : null
}
