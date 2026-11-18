# Seguridad

## Matriz IAM

Permisos de la función clasificadora. Cada uno acotado al recurso mínimo.

| Permiso | Recurso | Justificación |
|---|---|---|
| `s3:GetObject` | `bucket/uploads/*` | Leer la foto que disparó el evento. Solo el prefijo de entrada |
| `rekognition:DetectLabels` | `*` | Obtener etiquetas. La operación no expone ARN de recurso, así que IAM no permite acotarla |
| `dynamodb:PutItem`, `GetItem` | tabla de clasificaciones | Guardar el resultado y verificar duplicados antes de pagar una clasificación. Sin `Scan` |
| `sqs:SendMessage` | cola de errores | Enviar los eventos que fallaron. No puede leer ni borrar la cola |
| `logs:CreateLogStream`, `PutLogEvents` | log group de la función | Escribir logs. Sin `CreateLogGroup`: el grupo lo crea Terraform con retención de 7 días |

Otras identidades:

| Identidad | Permisos | Justificación |
|---|---|---|
| Rol `pixelpaws-ci` | `AdministratorAccess` | El pipeline crea roles, políticas y el presupuesto. Solo entrega credenciales temporales, de 12 horas como máximo |
| Usuario IAM `gustavo` | `AdministratorAccess` | Acceso por CLI del segundo integrante. Se borra al cerrar el proyecto |
| Usuario IAM `pixelpaws-emisor` | solo `sts:AssumeRole` sobre `pixelpaws-ci` | Genera las credenciales de 12 horas del pipeline. Su clave vive solo en la PC de un integrante, nunca en el repositorio ni en GitHub. Se borra al cerrar el proyecto |

## Autenticación del pipeline

La cuenta usa el plan Free de AWS, que la ubica dentro de una organización administrada por AWS
con una política de control de servicios (SCP). Esa política bloquea crear proveedores OIDC, así
que GitHub Actions no puede usar identidad federada.

En su lugar, el pipeline recibe **credenciales temporales** del rol `pixelpaws-ci`, generadas con
`scripts/credenciales-ci.sh`. Vencen solas: 12 horas desde un usuario IAM (se usa
`pixelpaws-emisor`, que solo puede asumir ese rol), 1 hora desde una sesión federada. No hay claves de acceso permanentes en el repositorio ni en los secrets.

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
| `CKV_AWS_28` | Point in time recovery en DynamoDB | Duplica el costo de almacenamiento y los datos se regeneran reprocesando las fotos |
| `CKV2_AWS_62` | Notificaciones de eventos en el bucket | Falso positivo: la notificación existe, en `aws_s3_bucket_notification` del módulo `clasificador`. Checkov no la relaciona con el bucket porque está en otro módulo |
| `CKV_AWS_116` | DLQ en la función | Falso positivo: la DLQ está en la configuración de invocación asincrónica (`aws_lambda_function_event_invoke_config`, `on_failure`), que es lo correcto para eventos de S3. Checkov solo revisa `dead_letter_config` |
| `CKV_AWS_338` | Logs retenidos al menos un año | La consigna exige 7 días |
| `CKV_AWS_117` | Lambda dentro de una VPC | La función solo usa servicios gestionados. En una VPC necesitaría un NAT Gateway, unos USD 32 por mes: el costo fijo que la consigna pide evitar |
| `CKV_AWS_50` | Trazas de X-Ray | Con un solo salto no aportan. El dashboard y los logs cubren la observabilidad que pide la consigna |
| `CKV_AWS_272` | Firma de código | Requiere AWS Signer. El paquete lo construye y despliega solo el pipeline de este repositorio |
| `CKV2_AWS_61` | Regla de vencimiento en el bucket | Borraría las fotos del lote antes de la defensa. El bucket se destruye al cerrar el proyecto |
| `CKV_AWS_119`, `CKV_AWS_158`, `CKV_AWS_173`, `CKV_AWS_26`, `CKV_AWS_145` | Clave KMS propia en DynamoDB, logs, variables de la Lambda, SNS y S3 | Cada clave cuesta USD 1 por mes, el 10% del presupuesto. Todo se cifra igual con claves de AWS. La única variable de entorno es el nombre de la tabla, y SNS solo transporta el texto de la alarma |
