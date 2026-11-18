resource "aws_s3_bucket" "fotos" {
  bucket = "${var.nombre}-fotos-${var.sufijo}"

  # Solo para el laboratorio: permite que destroy borre el bucket con objetos
  # dentro. La consigna evalua "destroy limpio".
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "fotos" {
  bucket                  = aws_s3_bucket.fotos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "fotos" {
  bucket = aws_s3_bucket.fotos.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "fotos" {
  bucket = aws_s3_bucket.fotos.id

  rule {
    apply_server_side_encryption_by_default {
      # SSE-S3 y no KMS: una clave gestionada por el cliente cuesta USD 1 al mes
      # y el presupuesto del proyecto es USD 10. Decision consciente, no olvido.
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Marcadores de los dos prefijos. No son obligatorios en S3, que no tiene
# carpetas reales, pero dejan la estructura visible en la consola para la demo.
resource "aws_s3_object" "prefijos" {
  for_each = toset([var.prefijo_entrada, var.prefijo_salida])

  bucket  = aws_s3_bucket.fotos.id
  key     = each.value
  content = ""
}
