output "topico_arn" {
  value = aws_sns_topic.alertas.arn
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.pixelpaws.dashboard_name}"
}
