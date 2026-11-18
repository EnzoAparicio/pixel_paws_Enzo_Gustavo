output "funcion_name" {
  value = aws_lambda_function.clasificador.function_name
}

output "funcion_arn" {
  value = aws_lambda_function.clasificador.arn
}

output "dlq_name" {
  value = aws_sqs_queue.dlq.name
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "rol_arn" {
  value = aws_iam_role.clasificador.arn
}
