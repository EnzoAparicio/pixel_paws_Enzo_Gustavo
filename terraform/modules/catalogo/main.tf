resource "aws_dynamodb_table" "clasificaciones" {
  name = "${var.nombre}-clasificaciones"

  # On-demand: cobra por escritura, no por capacidad reservada.
  billing_mode = "PAY_PER_REQUEST"

  # La clave es el nombre del archivo: reprocesar una foto no la duplica.
  hash_key = "archivo"

  attribute {
    name = "archivo"
    type = "S"
  }

  # PITR apagado: duplica el costo y los datos se regeneran reprocesando las fotos.
  point_in_time_recovery {
    enabled = false
  }

  server_side_encryption {
    enabled = true
  }
}
