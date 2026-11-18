resource "aws_s3_bucket" "fotos" {
  bucket = "${var.nombre}-fotos-${var.sufijo}"

  # Permite que destroy borre el bucket con fotos dentro: la consigna evalua
  # "destroy limpio".
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
      # SSE-S3 y no KMS: una clave propia cuesta USD 1 al mes con un
      # presupuesto de USD 10.
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}
