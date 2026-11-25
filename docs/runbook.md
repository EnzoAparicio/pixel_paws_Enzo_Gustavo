# Runbook de PixelPaws

Guía completa para desplegar, configurar, operar, validar y dar de baja PixelPaws en una cuenta
de AWS desde cero. No hace falta conocer el proyecto de antes: todo lo necesario está acá o
enlazado desde acá.

Tiempo estimado la primera vez: **40 minutos**, de los cuales unos 5 son de espera.

| Parte | Qué cubre | Cuándo se hace |
|---|---|---|
| [1. Requisitos](#1-requisitos) | Qué hace falta antes de empezar | Una vez |
| [2. Preparar la cuenta](#2-preparar-la-cuenta) | Usuario, MFA, región | Una vez |
| [3. Bootstrap](#3-bootstrap-estado-remoto-y-rol-del-pipeline) | Bucket del estado y rol del pipeline | Una vez |
| [4. Desplegar](#4-desplegar) | `init`, `plan`, `apply` | Cada cambio |
| [5. Configurar](#5-configurar-despues-del-primer-apply) | Mails de alerta y etiqueta de costos | Una vez |
| [6. Validar](#6-validar-que-funciona) | Prueba de humo, lote de 20 y camino de error | Después de cada apply |
| [7. Operar](#7-operar) | Dashboard, logs, consultas, DLQ | Día a día |
| [8. El pipeline](#8-el-pipeline-de-github) | CI en PR, apply en merge, destroy manual | Una vez y luego solo renovar |
| [9. Recuperación ante fallos](#9-recuperacion-ante-fallos) | Qué hacer cuando algo se rompe | Cuando haga falta |
| [10. Dar de baja](#10-dar-de-baja) | `destroy` y limpieza final | Al cerrar |

---

## 1. Requisitos

- Una cuenta de AWS donde se puedan crear roles de IAM. Sirve una cuenta propia en **plan Free**:
  da USD 100 de crédito y se suspende en vez de cobrar.
- **Terraform 1.17** o superior. La versión exacta que usa el pipeline es `1.17.2`.
- **AWS CLI v2** autenticado.
- Opcional, para el pipeline: la **CLI de GitHub** (`gh`) autenticada.

Todo se despliega en **`us-east-2` (Ohio)**. La región está fijada como valor por defecto en
`terraform/variables.tf` y validada: solo se aceptan `us-east-1`, `us-east-2` y `us-west-2`,
que son las de menor costo.

> **Sobre esta cuenta en particular.** La cuenta usada en el proyecto está dentro de una
> organización administrada por AWS, con una política de control de servicios (SCP) que solo
> habilita `us-east-2`, niega las contraseñas de consola para usuarios IAM y **niega crear
> proveedores OIDC**. Eso condiciona el paso 8. El detalle está en
> [`Decision 01`](Decision%2001%20-%20cuenta%20AWS%20Academy%20y%20brechas%20de%20la%20consigna.md).
> En una cuenta sin esa restricción, OIDC funciona: el código está escrito y se activa con
> `enable_oidc = true`.

### Dónde correr los comandos

Cualquiera de estas tres opciones sirve:

- **AWS CloudShell**, desde la consola, con la región en Ohio. Es lo más simple: ya trae el CLI
  autenticado. Hay que instalar Terraform (ver abajo).
- Una **máquina local** con el AWS CLI configurado.
- **GitHub Actions**, una vez hecho el paso 8.

Si se usa CloudShell, Terraform no viene instalado. Se instala una vez en `~/bin`, que persiste
entre sesiones:

```bash
VER=1.17.2
ARQ=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
mkdir -p ~/bin && cd /tmp
curl -fsSLO "https://releases.hashicorp.com/terraform/${VER}/terraform_${VER}_linux_${ARQ}.zip"
unzip -o "terraform_${VER}_linux_${ARQ}.zip" terraform -d ~/bin
grep -q 'HOME/bin' ~/.bashrc || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/bin:$PATH"
terraform version
```

---

## 2. Preparar la cuenta

Si la cuenta ya existe y tiene un usuario con permisos, saltear al paso 3.

**2.1 Proteger el usuario raíz.** Arriba a la derecha en la consola, *Security credentials* →
**Assign MFA device**. El raíz no se usa para trabajar.

**2.2 Usuario de trabajo.** Con el raíz, una sola vez:

- IAM → Users → Create user.
- Permisos: `AdministratorAccess`. Hace falta porque Terraform crea roles de IAM, políticas y
  el presupuesto de AWS Budgets.
- Activar MFA también en este usuario.

> Si la cuenta está en una organización que niega las contraseñas de consola para usuarios IAM,
> este usuario no va a poder entrar por la web. En ese caso se trabaja con el raíz para el
> bootstrap y se usa el usuario solo por CLI con access keys.

**2.3 Facturación visible para usuarios IAM.** Con el raíz: Account → *IAM user and role access
to Billing information* → Edit → Activate. Sin esto no se puede hacer el paso 5.2.

**2.4 Verificar la identidad y la región** antes de seguir:

```bash
aws sts get-caller-identity
aws configure get region   # tiene que decir us-east-2
```

---

## 3. Bootstrap: estado remoto y rol del pipeline

Terraform guarda su estado en S3, pero ese bucket no lo puede crear Terraform (sería un huevo y
la gallina). Lo crea un script, una sola vez.

```bash
git clone https://github.com/<owner>/<repo>.git
cd <repo>
bash bootstrap/bootstrap.sh
```

El script hace cuatro cosas sobre el bucket y una quinta sobre IAM:

| Qué crea | Por qué |
|---|---|
| Bucket `tfstate-pixelpaws-<sufijo>` | Guarda el estado de Terraform |
| Versionado | Permite volver atrás si el estado se corrompe |
| Cifrado AES256 en reposo | El estado contiene nombres de recursos y ARNs |
| Bloqueo de acceso público | El estado nunca debe ser legible desde Internet |
| Rol `pixelpaws-ci` | Lo asume el pipeline. Sesiones de hasta 12 horas |

Al terminar imprime el nombre del bucket. **Copiarlo**: va en el paso siguiente.

Para un nombre de bucket predecible en vez de aleatorio, se le pasa un sufijo:
`bash bootstrap/bootstrap.sh miequipo`.

**3.1 Completar `terraform/backend.hcl`** con ese nombre:

```hcl
bucket       = "tfstate-pixelpaws-31497"
key          = "pixelpaws/dev/terraform.tfstate"
region       = "us-east-2"
encrypt      = true
use_lockfile = true
```

`use_lockfile = true` usa el bloqueo nativo de S3 y evita tener que crear una tabla de DynamoDB
solo para eso. Requiere Terraform 1.10 o superior.

El nombre del bucket no es un secreto, así que esta línea se commitea.

---

## 4. Desplegar

**4.1 Variables que no están en el repositorio.** El repositorio es público, así que los correos
no se versionan. Hay que exportarlas en cada sesión nueva:

```bash
export TF_VAR_emails_alerta='["mail-1@ejemplo.com","mail-2@ejemplo.com"]'
export TF_VAR_equipo="aparicio-gonzalez"
export TF_VAR_owner="enzo-aparicio"
```

`equipo` y `owner` también pueden quedar fijos en `terraform/terraform.tfvars`, que sí está
versionado. Los correos no.

**4.2 Init, plan y apply:**

```bash
terraform -chdir=terraform init -backend-config=backend.hcl
terraform -chdir=terraform plan
terraform -chdir=terraform apply
```

El `plan` de la primera vez tiene que decir `Plan: N to add, 0 to change, 0 to destroy`. **Si
aparece algún `destroy` en el primer plan, hay que parar y revisar**: significa que el estado
apunta a recursos que no corresponden.

El `apply` tarda unos dos minutos. Al terminar muestra las salidas:

```
bucket           = "pixelpaws-dev-fotos-ca1889"
tabla            = "pixelpaws-dev-clasificaciones"
funcion          = "pixelpaws-dev-clasificador"
dlq              = "https://sqs.us-east-2.amazonaws.com/.../pixelpaws-dev-dlq"
dashboard_url    = "https://console.aws.amazon.com/cloudwatch/..."
comando_consulta = "aws dynamodb scan --table-name ..."
```

**La notificación de S3 tarda entre 3 y 6 minutos en propagarse** después del primer apply. Si
la prueba de humo del paso 6 falla enseguida, es esto: esperar y repetir antes de diagnosticar
cualquier otra cosa.

---

## 5. Configurar después del primer apply

**5.1 Confirmar las suscripciones de correo.** A cada dirección de `emails_alerta` le llega un
mail de **AWS Notifications** pidiendo confirmar. Hay que hacer clic en *Confirm subscription*
en cada una. **Sin esto la alarma se dispara pero no avisa a nadie**, que es el error más común
y el más silencioso.

Verificar que quedaron confirmadas:

```bash
aws sns list-subscriptions --region us-east-2 \
  --query "Subscriptions[?contains(TopicArn,'pixelpaws')].[Endpoint,SubscriptionArn]" --output table
```

Si en lugar de un ARN aparece `PendingConfirmation`, esa dirección todavía no confirmó.

**5.2 Activar la etiqueta de costos.** El presupuesto filtra el gasto por la etiqueta
`project = pixelpaws`, y AWS no contabiliza por etiqueta hasta que se la activa a mano:

Billing and Cost Management → **Cost allocation tags** → buscar `project` → **Activate**.

La etiqueta aparece en esa lista recién unas horas después del primer apply. Sin este paso el
presupuesto va a marcar USD 0 aunque haya gasto real.

---

## 6. Validar que funciona

### 6.1 Prueba de humo: una foto

```bash
BUCKET="$(terraform -chdir=terraform output -raw bucket)"
TABLA="$(terraform -chdir=terraform output -raw tabla)"

aws s3 cp pruebas/lote/perro01.jpg "s3://$BUCKET/uploads/humo.jpg"
sleep 15
aws dynamodb get-item --table-name "$TABLA" --region us-east-2 \
  --key '{"archivo":{"S":"uploads/humo.jpg"}}'
```

Tiene que devolver un item con `etiqueta`, `confianza` y `fecha`. La latencia típica medida es
de **240 a 480 ms** por foto; los 15 segundos de espera son holgura.

Si no aparece nada, ver el paso 9.

### 6.2 Lote de 20 fotos

```bash
export BUCKET TABLA
bash scripts/lote.sh
```

Sube las 20 fotos de `pruebas/lote/`, espera a que se clasifiquen y muestra la tabla de
resultados. El resultado de referencia es **20 de 20 clasificadas correctamente**, 10 gatos y
10 perros, con la confianza más baja en 94,18 %.

El script es idempotente: si se corre dos veces, la función detecta que el archivo ya está en la
tabla y no vuelve a llamar a Rekognition. Para ver los resultados sin volver a subir nada:
`bash scripts/lote.sh -c`.

### 6.3 El camino de error

Esta es la validación que demuestra que el sistema falla de forma controlada. Se sube un archivo
que no es una imagen pero tiene extensión `.jpg`:

```bash
echo "Esto no es una imagen" > /tmp/foto-rota.jpg
aws s3 cp /tmp/foto-rota.jpg "s3://$BUCKET/uploads/foto-rota.jpg"
```

Lo que pasa a continuación, y en cuánto tiempo:

| Momento | Qué ocurre | Dónde se ve |
|---|---|---|
| 0 s | Lambda se invoca y Rekognition devuelve `InvalidImageFormatException` | CloudWatch Logs |
| ~1 min | Segundo intento, falla igual | CloudWatch Logs |
| ~2 min | Tercer intento, falla igual. Se agotan los reintentos | CloudWatch Logs |
| ~2 min | El evento va a la cola de errores | SQS `pixelpaws-dev-dlq` |
| ~5 min | La alarma pasa a `ALARM` | CloudWatch Alarms |
| ~5 min | Llega el correo | Bandeja de entrada |

Para seguirlo en vivo:

```bash
# los logs, a medida que ocurren
aws logs tail "/aws/lambda/$(terraform -chdir=terraform output -raw funcion)" --follow --region us-east-2

# cuántos mensajes hay en la cola de errores
aws sqs get-queue-attributes --region us-east-2 \
  --queue-url "$(terraform -chdir=terraform output -raw dlq)" \
  --attribute-names ApproximateNumberOfMessagesVisible

# estado de la alarma
aws cloudwatch describe-alarms --region us-east-2 \
  --alarm-names pixelpaws-dev-dlq-con-mensajes \
  --query "MetricAlarms[0].[AlarmName,StateValue]" --output text
```

La alarma tiene acción solo en `ALARM`, no en `OK`: una vez que suena, queda sonando hasta que
se vacía la cola y se la reinicia a mano. Es deliberado, para que un error no pase inadvertido.

---

## 7. Operar

### Dashboard

El enlace sale de `terraform -chdir=terraform output -raw dashboard_url`. Muestra invocaciones,
errores, duración y profundidad de la cola de errores.

### Consultar las clasificaciones

```bash
aws dynamodb scan --table-name "$TABLA" --region us-east-2 \
  --projection-expression 'archivo,etiqueta,confianza,fecha'
```

El comando exacto también sale de `terraform -chdir=terraform output -raw comando_consulta`.

### Logs

```bash
aws logs tail "/aws/lambda/pixelpaws-dev-clasificador" --since 1h --region us-east-2
```

La retención está fijada en 7 días para no acumular costo.

### Vaciar la cola de errores

Después de revisar por qué cayó algo ahí:

```bash
aws sqs purge-queue --region us-east-2 --queue-url "$(terraform -chdir=terraform output -raw dlq)"
```

La alarma vuelve a `OK` sola unos minutos después.

### Costos

El presupuesto está fijado en **USD 10 al mes** y avisa por correo al 80 % y al 100 %. El costo
real del proyecto completo, incluyendo desarrollo, lote y demo, fue de **USD 0,0021**. La
proyección a 100.000 fotos por mes es de unos **USD 105**, de los cuales el 95 % es Rekognition.
El desglose está en
[`FinOps`](FinOps%20-%20estimacion%20y%20proyeccion%20PixelPaws.md).

---

## 8. El pipeline de GitHub

Tres flujos de trabajo:

| Flujo | Cuándo corre | Qué hace |
|---|---|---|
| `ci` | En cada pull request | `fmt`, `validate`, `tflint`, Checkov y publica el `plan` como comentario |
| `apply` | Al mergear a `main` | `apply`, con aprobación manual del entorno `production` |
| `destroy` | Manual | Destruye todo. Pide la aprobación del entorno `production` |

### 8.1 Cómo entra GitHub a AWS

Lo correcto sería OIDC, y el código está escrito en el módulo `cicd_oidc`. **Está apagado**
(`enable_oidc = false`) porque la SCP de la organización niega crear el proveedor. En su lugar:

1. Un usuario IAM llamado `pixelpaws-emisor` cuyo **único permiso es `sts:AssumeRole`** sobre el
   rol `pixelpaws-ci`. No puede hacer nada más en la cuenta.
2. Ese usuario asume `pixelpaws-ci` y obtiene credenciales temporales de 12 horas.
3. Esas credenciales se cargan como secrets de GitHub.

```bash
AWS_PROFILE=pixelpaws-emisor bash scripts/credenciales-ci.sh
```

Si `gh` está autenticado, el script carga los tres secrets solo. Si no, los imprime para pegarlos
a mano en *Settings → Secrets and variables → Actions*:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

**Vencen a las 12 horas.** Si el pipeline falla con un error de credenciales expiradas, se vuelve
a correr el script. Nunca se guarda una clave permanente en el repositorio ni en los secrets.

Hace falta además el secret `EMAILS_ALERTA` con la misma lista JSON del paso 4.1. Ese no vence.

### 8.2 Entorno con aprobación

*Settings → Environments → New environment* → `production`:

- **Required reviewers**: los integrantes del equipo.
- **Prevent self-review** activado, para que quien abre el cambio no sea quien lo aprueba.

Esto es lo que convierte el `apply` en controlado. En repositorios privados del plan gratuito los
revisores obligatorios no están disponibles: el repositorio tiene que ser público.

---

## 9. Recuperación ante fallos

### La foto se subió y no aparece en la tabla

En orden, porque el primero es el caso más frecuente:

1. **¿Pasaron menos de 6 minutos desde el primer apply?** La notificación de S3 tarda en
   propagarse. Esperar y repetir.
2. **¿La foto está bajo `uploads/`?** El disparador tiene un filtro de prefijo. Una foto en la
   raíz del bucket no dispara nada.
3. **¿Hay errores en los logs?**
   `aws logs tail "/aws/lambda/pixelpaws-dev-clasificador" --since 10m --region us-east-2`
4. **¿Está en la cola de errores?** Si sí, el archivo no era una imagen válida o Rekognition la
   rechazó.

### El estado de Terraform quedó bloqueado

```
Error acquiring the state lock
```

Hay otro `plan` o `apply` corriendo, o uno que se cortó a la mitad. Si no hay nada corriendo:

```bash
terraform -chdir=terraform force-unlock <ID-del-lock>
```

### El estado se corrompió

El bucket tiene versionado activado. Se lista el historial y se restaura la versión anterior:

```bash
aws s3api list-object-versions --bucket <bucket-del-estado> \
  --prefix pixelpaws/dev/terraform.tfstate
aws s3api get-object --bucket <bucket-del-estado> \
  --key pixelpaws/dev/terraform.tfstate --version-id <ID> terraform.tfstate.recuperado
```

### El pipeline no puede entrar a AWS

Casi siempre son las credenciales temporales vencidas: duran 12 horas. Volver a correr
`scripts/credenciales-ci.sh`.

### Se borró un recurso a mano desde la consola

```bash
terraform -chdir=terraform plan    # muestra lo que falta
terraform -chdir=terraform apply   # lo vuelve a crear
```

Esa es la ventaja de tener todo como código: el estado deseado está escrito y se reconstruye.

### Se perdieron los datos de la tabla

DynamoDB está en modo bajo demanda sin respaldo automático configurado, porque el catálogo es
reconstruible: las fotos siguen en S3. Para rehacerlo, se vuelven a copiar los objetos sobre el
prefijo `uploads/` y la función los reprocesa.

### Tabla rápida de errores conocidos

| Error | Causa | Solución |
|---|---|---|
| `IllegalLocationConstraintException` | Crear un bucket fuera de `us-east-1` sin `LocationConstraint` | Ya corregido en `bootstrap.sh` |
| `Error acquiring the state lock` | Otro apply corriendo o cortado | Esperar, o `force-unlock` |
| `AccessDenied ... explicit deny in a service control policy` | La SCP de la organización bloquea la acción | No se puede sortear desde la cuenta. Ver `Decision 01` |
| `ExpiredToken` en el pipeline | Credenciales de 12 h vencidas | Volver a correr `credenciales-ci.sh` |
| La alarma no manda correo | Suscripción sin confirmar | Paso 5.1 |
| El presupuesto marca USD 0 con gasto real | Etiqueta de costos sin activar | Paso 5.2 |
| `fmt -check` falla en el CI | Algún `.tf` sin formatear | `terraform fmt -recursive terraform/` |

---

## 10. Dar de baja

```bash
terraform -chdir=terraform destroy
```

O el flujo manual `destroy` en GitHub, que pide la aprobación del entorno `production` antes
de correr. Ese flujo deja además, en el
resumen de la ejecución, la lista de recursos que quedaron, como evidencia de que la cuenta
quedó limpia.

Después del `destroy` quedan tres cosas que Terraform no gestiona, porque son anteriores a él:

**1. El bucket del estado.** Tiene versionado, así que `aws s3 rb --force` no alcanza: no borra
las versiones antiguas. Desde la consola de S3, sobre el bucket `tfstate-pixelpaws-...`:
**Empty** y después **Delete**.

**2. El rol `pixelpaws-ci` y el usuario `pixelpaws-emisor`:**

```bash
aws iam detach-role-policy --role-name pixelpaws-ci \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-role --role-name pixelpaws-ci
```

Para el usuario hay que borrar primero sus access keys, listándolas con
`aws iam list-access-keys --user-name pixelpaws-emisor`.

**3. Los secrets de GitHub.** Las credenciales ya vencieron solas, pero conviene borrarlas.

### Verificar que no quedó nada

```bash
aws lambda list-functions --region us-east-2 \
  --query "Functions[?starts_with(FunctionName,'pixelpaws')].FunctionName"
aws dynamodb list-tables --region us-east-2 \
  --query "TableNames[?starts_with(@,'pixelpaws')]"
aws s3 ls | grep pixelpaws
```

Las tres tienen que volver vacías.
