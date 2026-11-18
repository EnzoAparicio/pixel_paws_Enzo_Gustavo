# Identidad federada para GitHub Actions. Elimina las claves de larga duracion
# que la consigna 2.4 prohibe explicitamente.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_oidc ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # thumbprint_list se omite a proposito. Desde 2023 IAM valida los proveedores
  # OIDC conocidos contra su propio almacen de confianza, asi que fijar una
  # huella a mano solo agrega algo que caduca y rompe el apply mas adelante.
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

    # Solo este repositorio. Sin esta condicion, cualquier repo de GitHub
    # podria asumir el rol.
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

# El pipeline administra toda la infraestructura del proyecto, asi que necesita
# permisos amplios sobre los servicios involucrados. Se acota por servicio y no
# se usa AdministratorAccess.
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

# No existe politica gestionada que permita administrar presupuestos: las de
# Budgets cubren las acciones automaticas, no la creacion. Va en linea.
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
