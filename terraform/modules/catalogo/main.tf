resource "aws_dynamodb_table" "clasificaciones" {
  name = "${var.nombre}-clasificaciones"

  # On-demand y no provisioned: el trafico es por lotes y esporadico, y
  # provisioned cobra por capacidad reservada aunque no se use.
  billing_mode = "PAY_PER_REQUEST"

  # Clave primaria: el nombre del archivo. Da idempotencia natural, un archivo
  # reprocesado sobreescribe su propio item en vez de duplicarlo.
  hash_key = "archivo"

  attribute {
    name = "archivo"
    type = "S"
  }

  # Point in time recovery apagado a proposito: duplica el costo de
  # almacenamiento y los datos del proyecto son regenerables reprocesando el lote.
  point_in_time_recovery {
    enabled = false
  }

  server_side_encryption {
    enabled = true
  }
}
