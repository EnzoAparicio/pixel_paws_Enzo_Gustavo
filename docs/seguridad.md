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
| Rol `pixelpaws-dev-github-actions` | Siete políticas por servicio más una en línea para presupuestos | Lo asume GitHub Actions por OIDC. **No tiene `AdministratorAccess`**: solo S3, Lambda, DynamoDB, SQS, CloudWatch, SNS, IAM y Budgets. Sesiones de 1 hora |
| Usuario IAM `gustavo` | `AdministratorAccess` | Acceso por CLI del segundo integrante. Se borra al cerrar el proyecto |

## Autenticación del pipeline: OIDC

**No hay ninguna clave de AWS guardada en GitHub.** El pipeline se autentica con OpenID Connect,
que es la forma recomendada por AWS para GitHub Actions.

Cómo funciona, en cuatro pasos:

1. GitHub Actions le pide a GitHub un token de identidad firmado para esa ejecución concreta.
   Ese token dice qué repositorio, qué rama y qué flujo lo pidieron.
2. El flujo se lo presenta a AWS STS junto con el ARN del rol que quiere asumir.
3. AWS valida la firma contra el proveedor OIDC `token.actions.githubusercontent.com`, que está
   registrado en la cuenta, y comprueba las dos condiciones de la política de confianza.
4. Si pasa, STS devuelve credenciales que **viven una hora y mueren solas**.

Las dos condiciones de confianza están en `terraform/modules/cicd_oidc/main.tf`:

| Condición | Valor | Para qué |
|---|---|---|
| `...:aud` | `sts.amazonaws.com` | El token tiene que haber sido emitido para STS, no para otro servicio |
| `...:sub` | `repo:OWNER/REPO:*` | **Solo este repositorio** puede asumir el rol. Otro repositorio, aunque esté en GitHub, no entra |

El rol se llama `pixelpaws-dev-github-actions` y **no tiene `AdministratorAccess`**: lleva siete
políticas gestionadas acotadas a los servicios que el proyecto usa, más una política en línea
para presupuestos, porque ninguna política gestionada de AWS cubre `budgets:ModifyBudget`.
Las sesiones duran 1 hora (`max_session_duration = 3600`).

El único secret de GitHub relacionado con AWS es `AWS_ROLE_ARN`, que es el ARN del rol. **Un ARN
no es un secreto**: sin un token OIDC válido emitido para el repositorio autorizado, conocerlo no
sirve de nada. Se guarda como secret por prolijidad, no por necesidad.

### Qué se gana contra el esquema anterior

El proyecto funcionó un tiempo con credenciales temporales de 12 horas generadas a mano con
`scripts/credenciales-ci.sh`, porque se creía que la cuenta no permitía crear el proveedor OIDC.
Resultó que sí lo permite. La diferencia es concreta:

| | Credenciales temporales | OIDC |
|---|---|---|
| Vida | 12 horas | 1 hora, por ejecución |
| Renovación | Manual, alguien corre un script | Automática |
| Qué se guarda en GitHub | Tres secrets con una credencial real | Un ARN |
| Si se filtran | Hay 12 horas de ventana | No hay nada que filtrar |
| Permisos | `AdministratorAccess` | Siete servicios acotados |

El script `scripts/credenciales-ci.sh` y el rol `pixelpaws-ci` se conservan como camino de
respaldo, por si hiciera falta operar desde una cuenta donde OIDC no esté disponible.

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
