resource "aws_sns_topic" "alertas" {
  name = "${var.nombre}-alertas"
}

resource "aws_sns_topic_subscription" "emails" {
  for_each = toset(var.emails_alerta)

  topic_arn = aws_sns_topic.alertas.arn
  protocol  = "email"
  endpoint  = each.value
}

# Alarma sobre la DLQ, la que pide la consigna: hay eventos que fallaron
# tres veces y quedaron guardados para reprocesar.
resource "aws_cloudwatch_metric_alarm" "dlq_con_mensajes" {
  alarm_name          = "${var.nombre}-dlq-con-mensajes"
  alarm_description   = "Hay eventos en la cola de errores: alguna foto no se pudo clasificar."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.dlq_name
  }

  alarm_actions = [aws_sns_topic.alertas.arn]
}

resource "aws_cloudwatch_dashboard" "pixelpaws" {
  dashboard_name = "${var.nombre}-pipeline"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Clasificaciones: invocaciones y errores"
          region = var.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.funcion_name],
            [".", "Errors", ".", ".", { color = "#d13212" }],
            [".", "Throttles", ".", "."],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Latencia de la clasificacion (ms)"
          region = var.region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.funcion_name, { stat = "Average" }],
            ["...", { stat = "Maximum" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Cola de errores (DLQ)"
          region = var.region
          view   = "timeSeries"
          stat   = "Maximum"
          period = 300
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.dlq_name, { color = "#d13212" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Escrituras en la tabla de clasificaciones"
          region = var.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.tabla_name],
          ]
        }
      },
    ]
  })
}
