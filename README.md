# PixelPaws Pets

Clasificador automatico de fotos de mascotas. Proyecto integrador de Cloud
Computing, Universidad Catolica del Uruguay, campus PDE, cursada 2026.

Equipo: Enzo Aparicio y Gustavo Gonzalez.

## Que hace

Una foto subida al bucket dispara un evento que invoca una funcion, la funcion
pide las etiquetas a un servicio de vision preentrenado y guarda el resultado en
una tabla NoSQL. Si algo falla, el evento termina en una cola de errores y una
alarma avisa.

```
Foto ──▶ S3 uploads/ ──▶ evento ObjectCreated ──▶ Lambda clasificador
                                                      │
                                   ┌──────────────────┼──────────────────┐
                                   ▼                  ▼                  ▼
                            Rekognition        DynamoDB            S3 clasificadas/
                            DetectLabels       archivo, etiqueta,  perros/ gatos/
                                               confianza, fecha    (extra)
                                   │
                          error tras 2 reintentos
                                   ▼
                              SQS DLQ ──▶ alarma CloudWatch ──▶ SNS ──▶ email
```

El diagrama de arquitectura con flujo de datos y limites de seguridad esta en
el vault, como nota de Excalidraw.

## Estructura

```
.
├── bootstrap/bootstrap.sh       # crea el bucket del estado, se corre una vez
├── lambda/clasificador.py       # la funcion
├── scripts/tf.sh                # plan | apply | destroy, local y en CI
├── scripts/smoke-test.sh        # prueba de punta a punta
├── terraform/
│   ├── versions.tf              # versiones ancladas y backend parcial
│   ├── variables.tf             # entradas con descripcion, tipo y validacion
│   ├── main.tf                  # composicion de modulos
│   ├── backend.hcl              # donde vive el estado
│   ├── terraform.tfvars         # valores del equipo
│   └── modules/
│       ├── almacenamiento/      # bucket privado, versionado, cifrado
│       ├── catalogo/            # tabla DynamoDB on-demand
│       ├── clasificador/        # Lambda, rol, DLQ, trigger
│       ├── observabilidad/      # dashboard, 2 alarmas, SNS
│       ├── finops/              # presupuesto con avisos 50/80/100
│       └── cicd_oidc/           # proveedor OIDC y rol de GitHub Actions
└── .github/workflows/           # ci (PR), apply (main), destroy (manual)
```

## Desplegar

### 1. Estado remoto, una sola vez

Desde AWS CloudShell, que ya viene autenticado:

```bash
git clone [<este-repo>](https://github.com/EnzoAparicio/pixel_paws_Enzo_Gustavo.git) && cd pixelpaws
bash bootstrap/bootstrap.sh
```

Copiar el nombre del bucket que imprime a `terraform/backend.hcl`.

### 2. Valores del equipo

El repositorio es publico, asi que los mails no van en el codigo. En CloudShell:

```bash
export TF_VAR_repositorio_github="<owner>/pixelpaws"
export TF_VAR_emails_alerta='["mail-enzo@ejemplo.com","mail-gustavo@ejemplo.com"]'
```

En GitHub, crear el secret `EMAILS_ALERTA` con la misma lista JSON. El repositorio lo
toma solo de `github.repository`.

### 3. Primer apply

```bash
./scripts/tf.sh apply
```

Confirmar la suscripcion de SNS en el correo, si no las alarmas no llegan.

### 4. Conectar el pipeline

```bash
terraform -chdir=terraform output -raw rol_github_arn
```

Ese ARN va como secret `AWS_ROLE_ARN` en el repositorio. No hay claves de
acceso: la autenticacion es por identidad federada OIDC.

Despues, en Settings -> Environments, crear `production` con revisores
obligatorios. Eso es lo que convierte el apply en controlado.

## Destruir

```bash
./scripts/tf.sh destroy
```

O el workflow manual `destroy`, escribiendo DESTRUIR en la confirmacion. Deja
en el resumen la evidencia de que no quedan recursos.

Al terminar el proyecto, borrar tambien el bucket del estado. Tiene versionado, asi
que `aws s3 rb --force` no alcanza: deja las versiones viejas y el bucket no se borra.
Lo mas simple es la consola de S3: el bucket `tfstate-pixelpaws-...` -> **Empty** ->
**Delete**.

## Matriz IAM

Permisos de la funcion clasificadora. Cada uno acotado al recurso minimo.

| Identidad | Permiso | Recurso | Justificacion |
|---|---|---|---|
| Rol de la funcion | `s3:GetObject` | `bucket/uploads/*` | Leer la foto que disparo el evento. Solo el prefijo de entrada |
| Rol de la funcion | `s3:PutObject` | `bucket/clasificadas/*` | Copiar la foto ya clasificada. Solo el prefijo de salida |
| Rol de la funcion | `rekognition:DetectLabels` | `*` | Obtener etiquetas. Rekognition no expone ARNs para esta operacion, asi que no admite restriccion por recurso |
| Rol de la funcion | `dynamodb:PutItem`, `GetItem` | tabla de clasificaciones | Guardar el resultado y verificar duplicados antes de pagar una clasificacion |
| Rol de la funcion | `sqs:SendMessage` | DLQ del proyecto | Enviar los eventos que fallaron |
| Rol de la funcion | `logs:CreateLogStream`, `PutLogEvents` | log group de la funcion | Escribir logs. El log group ya existe, creado por Terraform con retencion de 7 dias, asi que no necesita `CreateLogGroup` |
| Rol de GitHub Actions | administrar los servicios del proyecto | cuenta | Desplegar y destruir. Asumido por OIDC, sin claves de larga duracion, y restringido por `sub` a este repositorio |

## Hallazgos aceptados del escaneo

Checkov marca estos puntos. Se suprimen con justificacion escrita, no por
comodidad.

| Regla | Que pide | Por que se acepta |
|---|---|---|
| `CKV_AWS_18` | Access logging en el bucket | Un segundo bucket de logs duplica el almacenamiento y el proyecto tiene presupuesto de USD 10. La auditoria la cubre CloudTrail a nivel de cuenta |
| `CKV_AWS_144` | Replicacion cross region | Costo de transferencia entre regiones. La consigna pide una sola region elegida por menor costo |
| `CKV_AWS_28`, `CKV2_AWS_62` | Point in time recovery y notificaciones de evento en DynamoDB | PITR duplica el costo de almacenamiento y los datos son regenerables reprocesando el lote |
| `CKV_AWS_119` | Cifrado de DynamoDB con clave gestionada por el cliente | Una clave KMS propia cuesta USD 1 al mes, el 10% del presupuesto. Se usa el cifrado con clave de AWS |
| `CKV_AWS_158` | Cifrado de los log groups con KMS | Mismo motivo: la clave cuesta mas que todo el resto del proyecto |

## Riesgo de costo numero uno

No es el volumen, es la recursion. Si el extra `mover_clasificadas` escribe en
el mismo bucket y el filtro del evento no esta acotado a `uploads/`, la funcion
se invoca a si misma en loop y cada vuelta es una llamada paga a Rekognition.

Mitigacion: `filter_prefix = "uploads/"` en el notification, salida en
`clasificadas/`, y la alarma de la DLQ mas el presupuesto al 50% avisando.

La estimacion de costos y la proyeccion a escala de produccion estan en la nota
de FinOps del vault.
