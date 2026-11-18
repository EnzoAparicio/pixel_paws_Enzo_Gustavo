output "presupuesto_nombre" {
  value = var.enable_budget ? aws_budgets_budget.proyecto[0].name : null
}
