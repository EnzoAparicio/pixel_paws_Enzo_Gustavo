# PixelPaws Pets

Clasificador automático de fotos de mascotas en AWS. Proyecto integrador de Cloud Computing,
Universidad Católica del Uruguay, campus PDE, 2026.

Equipo: Enzo Aparicio y Gustavo Gonzalez.

## Qué hace

Una foto subida a `uploads/` en S3 dispara una función Lambda, que le pide las etiquetas a
Amazon Rekognition y guarda archivo, etiqueta, confianza y fecha en DynamoDB. Si la función
falla, el evento termina en una cola de errores (SQS) y una alarma de CloudWatch avisa por mail.

Diagrama de arquitectura: [`docs/arquitectura.html`](docs/arquitectura.html).

## Estructura

```
.
├── bootstrap/bootstrap.sh     # crea el bucket del estado y el rol del pipeline, una sola vez
├── lambda/                    # la función clasificadora
├── terraform/                 # raíz + 6 módulos: almacenamiento, catalogo, clasificador,
│                              # observabilidad, finops, cicd_oidc
├── scripts/
│   ├── lote.sh                # sube el lote de 20 fotos y muestra los resultados
│   └── credenciales-ci.sh     # credenciales temporales para el pipeline
├── pruebas/                   # fotos de prueba
├── docs/                      # diagrama, seguridad, FinOps y decisión de cuenta
└── .github/workflows/         # ci (PR), apply (merge a main), destroy (manual)
```

## Desplegar

Requiere Terraform 1.17 y el AWS CLI autenticado en la cuenta, región `us-east-2`.

1. **Estado remoto, una sola vez.** Crea el bucket del estado y el rol del pipeline:

   ```bash
   git clone https://github.com/EnzoAparicio/pixel_paws_Enzo_Gustavo.git
   cd pixel_paws_Enzo_Gustavo
   bash bootstrap/bootstrap.sh
   ```

   Copiar el nombre del bucket que imprime en `terraform/backend.hcl`.

2. **Datos del equipo.** No están en el código porque el repositorio es público:

   ```bash
   export TF_VAR_repositorio_github="EnzoAparicio/pixel_paws_Enzo_Gustavo"
   export TF_VAR_emails_alerta='["mail-1@ejemplo.com","mail-2@ejemplo.com"]'
   ```

3. **Aplicar:**

   ```bash
   terraform -chdir=terraform init -backend-config=backend.hcl
   terraform -chdir=terraform apply
   ```

   Confirmar la suscripción en el mail de AWS Notifications, si no las alarmas no llegan.

**Pipeline:** en GitHub, crear el environment `production` con revisores obligatorios, y los
secrets `EMAILS_ALERTA` y las credenciales temporales que genera
`AWS_PROFILE=pixelpaws-emisor bash scripts/credenciales-ci.sh` (duran 12 horas). Por qué
credenciales temporales y no OIDC: [`docs/seguridad.md`](docs/seguridad.md).

## Destruir

```bash
terraform -chdir=terraform destroy
```

O el workflow manual `destroy` en GitHub, escribiendo `DESTRUIR`.

El bucket del estado queda: al cerrar el proyecto se borra desde la consola de S3 con
**Empty** y después **Delete** (tiene versionado, así que `aws s3 rb --force` no alcanza).

## Más información

- [`docs/seguridad.md`](docs/seguridad.md): matriz IAM, autenticación del pipeline y hallazgos aceptados de Checkov
- [`docs/FinOps - estimacion y proyeccion PixelPaws.md`](docs/FinOps%20-%20estimacion%20y%20proyeccion%20PixelPaws.md): costo real y proyección
- [`docs/Decision 01 - cuenta AWS Academy y brechas de la consigna.md`](docs/Decision%2001%20-%20cuenta%20AWS%20Academy%20y%20brechas%20de%20la%20consigna.md): elección de la cuenta
