locals {
  funcion_name = "${var.nombre}-clasificador"
  log_group    = "/aws/lambda/${local.funcion_name}"
  rol_arn      = var.crear_iam_propio ? aws_iam_role.clasificador[0].arn : var.rol_ejecucion_externo
}

data "aws_caller_identity" "actual" {}

# ------------------------------------------------------------------- DLQ
# S3 invoca a Lambda de forma ASINCRONICA, por eso la DLQ se declara en el
# event_invoke_config y no en el bloque dead_letter_config del trigger.
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.nombre}-dlq"
  message_retention_seconds = 345600 # 4 dias
  sqs_managed_sse_enabled   = true
}

# ------------------------------------------------------------------- IAM
data "aws_iam_policy_document" "asumir" {
  count = var.crear_iam_propio ? 1 : 0

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
  count              = var.crear_iam_propio ? 1 : 0
  name               = "${local.funcion_name}-rol"
  assume_role_policy = data.aws_iam_policy_document.asumir[0].json
}

# Menor privilegio real: cada permiso acotado al recurso minimo. Es la matriz
# IAM de la consigna expresada como codigo.
data "aws_iam_policy_document" "permisos" {
  count = var.crear_iam_propio ? 1 : 0

  statement {
    sid       = "LeerFotosSinClasificar"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.bucket_arn}/${var.prefijo_entrada}*"]
  }

  statement {
    sid       = "EscribirFotosClasificadas"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.bucket_arn}/${var.prefijo_salida}*"]
  }

  statement {
    sid    = "ClasificarImagen"
    effect = "Allow"
    # DetectLabels no admite permisos a nivel de recurso: Rekognition no
    # expone ARNs para esta operacion. Documentado, no es un descuido.
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
  count  = var.crear_iam_propio ? 1 : 0
  name   = "${local.funcion_name}-politica"
  role   = aws_iam_role.clasificador[0].id
  policy = data.aws_iam_policy_document.permisos[0].json
}

# ------------------------------------------------------------------- funcion
# El log group se declara explicitamente para que Terraform controle la
# retencion de 7 dias que exige la consigna. Si lo crea Lambda, queda "nunca
# expira" y genera costo.
resource "aws_cloudwatch_log_group" "clasificador" {
  name              = local.log_group
  retention_in_days = var.retencion_logs_dias
}

resource "aws_lambda_function" "clasificador" {
  function_name = local.funcion_name
  role          = local.rol_arn
  handler       = "clasificador.handler"
  runtime       = "python3.12"
  architectures = ["arm64"] # Graviton: mismo rendimiento, 20% mas barato

  filename         = var.zip_path
  source_code_hash = var.zip_hash

  memory_size = var.memoria_mb
  timeout     = var.timeout_seg

  environment {
    variables = {
      TABLA_DYNAMODB     = var.tabla_name
      PREFIJO_SALIDA     = var.prefijo_salida
      MIN_CONFIANZA      = tostring(var.min_confianza)
      MOVER_CLASIFICADAS = tostring(var.mover_clasificadas)
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

    # ESTE FILTRO ES LO QUE EVITA LA RECURSION. Si se quita y
    # mover_clasificadas esta en true, la funcion se invoca a si misma en loop
    # y cada vuelta es una llamada paga a Rekognition.
    filter_prefix = var.prefijo_entrada
  }

  # Sin este depends_on, S3 intenta validar el destino antes de que exista el
  # permiso y el apply falla. Es la dependencia circular clasica del par
  # notification / permission.
  depends_on = [aws_lambda_permission.desde_s3]
}
