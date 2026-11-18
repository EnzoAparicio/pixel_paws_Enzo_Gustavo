---
up:
  - "[[Cloud Computing MOC]]"
related:
  - "[[Plan PixelPaws Pets - proyecto integrador]]"
  - "[[Decision 01 - cuenta AWS Academy y brechas de la consigna]]"
created: 2026-11-11
tema: "Estimación FinOps de PixelPaws Pets: costo real del desarrollo y proyección a escala de producción"
tipo: entregable
in:
  - "[[Cloud Computing MOC]]"
---

# FinOps - PixelPaws Pets

> Entregable común 2.6 de la consigna: *"estimación FinOps (costo real facturado + proyección a
> escala de producción)"*. Peso en la rúbrica: 10%.
> Los precios son de `us-east-2` (Ohio), verificados el 11/11/2026 contra las páginas
> oficiales de AWS. Ohio está en la misma franja tarifaria que `us-east-1` para los siete
> servicios del proyecto, así que las cifras valen igual.

## 1. Marco de la cuenta

| Dato | Valor | Fuente |
|---|---|---|
| Créditos al alta | USD 100 | Docs de facturación de AWS |
| Créditos adicionales por actividades | hasta USD 100 | Docs de facturación de AWS |
| Plan elegido | Free account plan | Decisión 01 |
| Posibilidad de cargo | Ninguna sin upgrade manual | *"You will not incur any charges during this period until you upgrade to a paid account plan"* |
| Fin del plan | 6 meses o créditos agotados, lo que ocurra primero | Docs de facturación |
| Al finalizar | Suspensión, no cobro. Datos retenidos 90 días | FAQ del free tier |
| Presupuesto declarado en Terraform | USD 10 con avisos al 50, 80 y 100% | Exigencia de la consigna |

Nota importante: en el plan Free solo están activas las ofertas **Always Free**. Los trials de
12 meses no aplican, así que el free tier propio de Rekognition (1.000 imágenes por mes) no
está disponible y ese consumo se descuenta de los créditos.

## 2. Precios unitarios usados

| Servicio | Unidad | Precio | Always Free aplicable |
|---|---|---|---|
| Rekognition `DetectLabels` (Grupo 2) | por imagen, primer millón mensual | USD 0.001 | No en plan Free |
| Lambda | por GB-segundo | USD 0.0000166667 | 400.000 GB-s y 1M requests al mes |
| DynamoDB on-demand | por millón de unidades de escritura | USD 1.25 | 25 GB de almacenamiento |
| S3 Standard | por GB-mes | USD 0.023 | No en plan Free |
| S3 PUT | por 1.000 requests | USD 0.005 | No en plan Free |
| SQS | por millón de requests | USD 0.40 | 1M requests al mes |
| CloudWatch alarmas | por alarma estándar | USD 0.10 | 10 alarmas |
| CloudWatch logs ingesta | por GB | USD 0.50 | 5 GB al mes |
| SNS email | por 1.000 notificaciones | USD 2.00 | 1.000 al mes |

## 3. Costo real del desarrollo y la demo

Supuesto de volumen: 300 imágenes procesadas en total entre desarrollo, pruebas, el lote
obligatorio de 20 fotos y la demo. Lambda a 256 MB y 3 s por invocación.

| Concepto | Cálculo | Costo |
|---|---|---|
| Rekognition | 300 x USD 0.001 | USD 0.300 |
| Lambda cómputo | 300 x 0.256 GB x 3 s = 230 GB-s, de 400.000 gratis | USD 0 |
| Lambda requests | 300, de 1.000.000 gratis | USD 0 |
| DynamoDB escrituras | 300 unidades | USD 0.0004 |
| DynamoDB almacenamiento | 300 items x 200 B = 60 KB | USD 0 |
| S3 PUT | 600 requests | USD 0.003 |
| S3 almacenamiento | 300 fotos x 2 MB = 600 MB x 1 mes | USD 0.014 |
| SQS | DLQ vacía salvo pruebas dirigidas | USD 0 |
| CloudWatch | 2 alarmas de 10 gratis, logs bajo 5 GB con retención 7 días | USD 0 |
| SNS | pocas notificaciones de prueba | USD 0 |
| **Total** | | **USD 0.32** |

Representa el **0.32% de los USD 100** de crédito. El margen de error no cambia la conclusión:
incluso multiplicando el volumen por 10 el costo queda en USD 3.20.

## 4. Proyección a escala de producción

Escenario: la veterinaria procesa **100.000 fotos por mes**.

| Concepto | Cálculo | Costo mensual | % del total |
|---|---|---|---|
| Rekognition | 100.000 x USD 0.001 | USD 100.00 | 95.0% |
| S3 almacenamiento | 200 GB x USD 0.023 | USD 4.60 | 4.4% |
| S3 PUT | 100.000 requests | USD 0.50 | 0.5% |
| DynamoDB escrituras | 100.000 unidades | USD 0.125 | 0.1% |
| Lambda | 76.800 GB-s, bajo los 400.000 gratis | USD 0 | 0% |
| DynamoDB almacenamiento | 20 MB, bajo los 25 GB gratis | USD 0 | 0% |
| SQS, SNS, CloudWatch | bajo los allowances | USD 0 | 0% |
| **Total** | | **USD 105.23** | |

### La conclusión que importa

**El 95% del costo a escala es la API de visión.** La infraestructura serverless que rodea a
Rekognition es efectivamente gratis incluso a 100.000 fotos por mes: Lambda sigue dentro del
Always Free y DynamoDB on-demand cuesta 12 centavos.

Eso invierte la intuición habitual. Optimizar la Lambda, bajar la memoria de 256 a 128 MB o
afinar la tabla no mueve la aguja: ahorra centavos sobre un total de USD 105. El único lugar
donde hay plata es en **no llamar a Rekognition**.

## 5. Medidas de ahorro, ordenadas por impacto

| Medida | Ahorro estimado | Cómo |
|---|---|---|
| **Deduplicación antes de clasificar (implementada)** | Todo reprocesamiento de una foto ya conocida | La función consulta DynamoDB con `GetItem` antes de llamar a Rekognition. Si el archivo ya está, lo saltea. Mejora posible: deduplicar por hash del contenido, para detectar la misma foto subida con otro nombre |
| Idempotencia del evento | Evita el reprocesamiento por reintentos | La clave primaria `archivo` ya impide duplicados en la tabla; agregar un `attribute_not_exists` en la condición de escritura |
| Bajar `MinConfidence` y `MaxLabels` | USD 0 | No afecta el precio, se cobra por imagen y no por etiqueta. Mencionado para descartarlo explícitamente |
| Retención de logs en 7 días | Mantiene CloudWatch en cero | Exigido por la consigna, ya contemplado |
| Banderas `enable_*` en recursos con costo por hora | Evita el único riesgo real de factura | PixelPaws no usa NAT, balanceador, base gestionada ni clúster, así que no hay costo por hora en toda la arquitectura |


## 6. Evidencia a capturar para la defensa

- [ ] Captura del presupuesto de USD 10 con los tres avisos configurados
- [ ] Captura de Cost Explorer o de la página de Bills mostrando el costo real facturado
- [ ] Captura del saldo de créditos antes y después de la demo
- [ ] Esta tabla de proyección, para responder "¿cuánto costaría en producción?"
