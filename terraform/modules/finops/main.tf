# Presupuesto con los tres avisos que pide la consigna. Detras de bandera
# porque AWS Academy Learner Lab no da acceso a facturacion.
resource "aws_budgets_budget" "proyecto" {
  count = var.enable_budget ? 1 : 0

  name         = "${var.nombre}-presupuesto"
  budget_type  = "COST"
  limit_amount = tostring(var.monto_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Filtra por la etiqueta obligatoria project, asi el presupuesto mide este
  # proyecto y no toda la cuenta.
  cost_filter {
    name   = "TagKeyValue"
    values = ["user:project$${var.proyecto}"]
  }

  # 50%: aviso temprano sobre gasto ya ocurrido.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.emails_alerta
  }

  # 80%: ventana para reaccionar antes de agotarlo.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.emails_alerta
  }

  # 100% previsto: avisa segun la proyeccion, no espera a que pase.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.emails_alerta
  }
}
