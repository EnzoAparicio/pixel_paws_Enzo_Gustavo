# OIDC para GitHub Actions; apagado porque la SCP de la cuenta lo bloquea.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_oidc ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # Sin thumbprint_list: IAM valida solo los proveedores OIDC conocidos.
}

data "aws_iam_policy_document" "confianza" {
  count = var.enable_oidc ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    # Solo tokens emitidos para STS.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Solo este repositorio puede asumir el rol.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.repositorio}:*"]
    }
  }
}

resource "aws_iam_role" "github" {
  count = var.enable_oidc ? 1 : 0

  name                 = "${var.nombre}-github-actions"
  description          = "Rol asumido por GitHub Actions via OIDC para plan, apply y destroy."
  assume_role_policy   = data.aws_iam_policy_document.confianza[0].json
  max_session_duration = 3600
}

# Permisos por servicio para administrar el proyecto, sin AdministratorAccess.
resource "aws_iam_role_policy_attachment" "github" {
  for_each = var.enable_oidc ? toset([
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/AWSLambda_FullAccess",
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/AmazonSQSFullAccess",
    "arn:aws:iam::aws:policy/CloudWatchFullAccess",
    "arn:aws:iam::aws:policy/AmazonSNSFullAccess",
    "arn:aws:iam::aws:policy/IAMFullAccess",
  ]) : toset([])

  role       = aws_iam_role.github[0].name
  policy_arn = each.value
}

# Ninguna politica gestionada permite crear presupuestos: va en linea.
data "aws_iam_policy_document" "presupuestos" {
  count = var.enable_oidc ? 1 : 0

  statement {
    sid    = "AdministrarPresupuestos"
    effect = "Allow"
    actions = [
      "budgets:ViewBudget",
      "budgets:ModifyBudget",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "presupuestos" {
  count  = var.enable_oidc ? 1 : 0
  name   = "${var.nombre}-presupuestos"
  role   = aws_iam_role.github[0].id
  policy = data.aws_iam_policy_document.presupuestos[0].json
}
