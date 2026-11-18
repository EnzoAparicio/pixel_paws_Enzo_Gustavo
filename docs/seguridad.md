# Seguridad

## Matriz IAM

Permisos de la función clasificadora. Cada uno acotado al recurso mínimo.

| Permiso | Recurso | Justificación |
|---|---|---|
| `s3:GetObject` | `bucket/uploads/*` | Leer la foto que disparó el evento. Solo el prefijo de entrada |
| `s3:PutObject` | `bucket/clasificadas/*` | Copiar la foto clasificada. Solo el prefijo de salida: no puede escribir donde lee |
| `rekognition:DetectLabels` | `*` | Obtener etiquetas. La operación no expone ARN de recurso, así que IAM no permite acotarla |
| `dynamodb:PutItem`, `GetItem` | tabla de clasificaciones | Guardar el resultado y verificar duplicados antes de pagar una clasificación. Sin `Scan` |
| `sqs:SendMessage` | cola de errores | Enviar los eventos que fallaron. No puede leer ni borrar la cola |
| `logs:CreateLogStream`, `PutLogEvents` | log group de la función | Escribir logs. Sin `CreateLogGroup`: el grupo lo crea Terraform con retención de 7 días |

Otras identidades:

| Identidad | Permisos | Justificación |
|---|---|---|
| Rol `pixelpaws-ci` | `AdministratorAccess` | El pipeline crea roles, políticas y el presupuesto. Solo entrega credenciales temporales, de 12 horas como máximo |
| Usuario IAM `gustavo` | `AdministratorAccess` | Acceso por CLI del segundo integrante. Se borra al cerrar el proyecto |

## Autenticación del pipeline

La cuenta usa el plan Free de AWS, que la ubica dentro de una organización administrada por AWS
con una política de control de servicios (SCP). Esa política bloquea crear proveedores OIDC, así
que GitHub Actions no puede usar identidad federada.

En su lugar, el pipeline recibe **credenciales temporales** del rol `pixelpaws-ci`, generadas con
`scripts/credenciales-ci.sh`. Vencen solas: 12 horas desde un usuario IAM, 1 hora desde una
sesión federada. No hay claves de acceso permanentes en el repositorio ni en los secrets.

El código de OIDC está escrito en `terraform/modules/cicd_oidc`, con `enable_oidc = false`:

```bash
terraform -chdir=terraform plan -var enable_oidc=true
```

## Hallazgos aceptados de Checkov

Se suprimen con justificación escrita, no por comodidad.

| Regla | Qué pide | Por qué se acepta |
|---|---|---|
| `CKV_AWS_18` | Access logging en el bucket | Un segundo bucket de logs duplica el almacenamiento con un presupuesto de USD 10. La auditoría la cubre CloudTrail a nivel de cuenta |
| `CKV_AWS_144` | Replicación entre regiones | Costo de transferencia, y la consigna pide una sola región |
| `CKV_AWS_28`, `CKV2_AWS_62` | Point in time recovery y notificaciones en DynamoDB | PITR duplica el costo de almacenamiento y los datos se regeneran reprocesando las fotos |
| `CKV_AWS_119` | DynamoDB cifrado con clave propia | Una clave KMS propia cuesta USD 1 por mes, el 10% del presupuesto. Se usa la clave de AWS |
| `CKV_AWS_158` | Log groups cifrados con KMS | Mismo motivo |

## Riesgo de recursión

Es el único riesgo real de factura. Si la copia a `clasificadas/` cayera en el prefijo que
dispara la función, la función se invocaría a sí misma en loop, pagando una llamada a
Rekognition por vuelta.

Mitigación: el aviso del bucket filtra por `uploads/`, la copia escribe en `clasificadas/`, la
función no tiene permiso de escribir en `uploads/`, y la copia está apagada por defecto
(`mover_clasificadas = false`).
