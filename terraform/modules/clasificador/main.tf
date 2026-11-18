locals {
  funcion_name = "${var.nombre}-clasificador"
  log_group    = "/aws/lambda/${local.funcion_name}"
  # Solo las fotos subidas a este prefijo disparan la funcion.
  prefijo_entrada = "uploads/"
}

data "aws_caller_identity" "actual" {}

# ------------------------------------------------------------------- DLQ
# S3 invoca a Lambda de forma ASINCRONICA, por eso la DLQ se declara en el
# event_invoke_config y no en el trigger.
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.nombre}-dlq"
  message_retention_seconds = 345600 # 4 dias
  sqs_managed_sse_enabled   = true
}

# ------------------------------------------------------------------- IAM
data "aws_iam_policy_document" "asumir" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "clasificador" {
  name               = "${local.funcion_name}-rol"
  assume_role_policy = data.aws_iam_policy_document.asumir.json
}

# Menor privilegio: cada permiso acotado al recurso minimo. Es la matriz IAM
# de la consigna expresada como codigo.
data "aws_iam_policy_document" "permisos" {
  statement {
    sid       = "LeerFotosSubidas"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.bucket_arn}/${local.prefijo_entrada}*"]
  }

  statement {
    sid    = "ClasificarImagen"
    effect = "Allow"
    # DetectLabels no admite permisos a nivel de recurso: Rekognition no
    # expone ARNs para esta operacion.
    actions   = ["rekognition:DetectLabels"]
    resources = ["*"]
  }

  statement {
    sid       = "GuardarYVerificarClasificacion"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem"]
    resources = [var.tabla_arn]
  }

  statement {
    sid       = "EnviarErroresALaDLQ"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }

  statement {
    sid       = "EscribirLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.actual.account_id}:log-group:${local.log_group}:*"]
  }
}

resource "aws_iam_role_policy" "clasificador" {
  name   = "${local.funcion_name}-politica"
  role   = aws_iam_role.clasificador.id
  policy = data.aws_iam_policy_document.permisos.json
}

# El rol y su politica antes tenian count (respaldo para Learner Lab). Estos
# bloques le dicen a Terraform que son los mismos recursos: sin ellos los
# borraria y los volveria a crear.
moved {
  from = aws_iam_role.clasificador[0]
  to   = aws_iam_role.clasificador
}

moved {
  from = aws_iam_role_policy.clasificador[0]
  to   = aws_iam_role_policy.clasificador
}

# ------------------------------------------------------------------- funcion
# El log group se declara para que Terraform controle la retencion de 7 dias
# que exige la consigna. Si lo crea Lambda, queda sin vencimiento.
resource "aws_cloudwatch_log_group" "clasificador" {
  name              = local.log_group
  retention_in_days = 7
}

resource "aws_lambda_function" "clasificador" {
  function_name = local.funcion_name
  role          = aws_iam_role.clasificador.arn
  handler       = "clasificador.handler"
  runtime       = "python3.12"
  architectures = ["arm64"] # Graviton: alrededor de 20% mas barato

  filename         = var.zip_path
  source_code_hash = var.zip_hash

  memory_size = 256 # 128 se queda corto por la espera de red a Rekognition
  timeout     = 30

  # Tope de gasto: nunca mas de 10 clasificaciones a la vez.
  reserved_concurrent_executions = 10

  environment {
    variables = {
      TABLA_DYNAMODB = var.tabla_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.clasificador,
    aws_iam_role_policy.clasificador,
  ]
}

# Invocacion asincronica: aca va la DLQ.
resource "aws_lambda_function_event_invoke_config" "clasificador" {
  function_name                = aws_lambda_function.clasificador.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600

  destination_config {
    on_failure {
      destination = aws_sqs_queue.dlq.arn
    }
  }
}

# ------------------------------------------------------------------- trigger
resource "aws_lambda_permission" "desde_s3" {
  statement_id   = "PermitirInvocacionDesdeS3"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.clasificador.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = var.bucket_arn
  source_account = data.aws_caller_identity.actual.account_id
}

resource "aws_s3_bucket_notification" "fotos" {
  bucket = var.bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.clasificador.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = local.prefijo_entrada
  }

  # Sin este depends_on, S3 valida el destino antes de que exista el permiso y
  # el apply falla.
  depends_on = [aws_lambda_permission.desde_s3]
}
