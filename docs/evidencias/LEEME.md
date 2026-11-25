# Evidencias del informe

Guardar acá cada captura **con este nombre exacto**. Después, en `informe.md`, buscar el nombre
del archivo y borrar `<!--` y `-->` de la línea de la imagen para que se muestre.

| Archivo | Qué capturar | Quién | Cuándo |
|---|---|---|---|
| `e01-pr-con-plan.png` | Un pull request con el comentario del `plan` | Enzo | Cuando corra el pipeline |
| `e02-apply-esperando-aprobacion.png` | El workflow `apply` esperando aprobación en `production` | Enzo | Cuando corra el pipeline |
| `e03-checkov.png` | El paso de Checkov en el workflow `ci` | Enzo | Cuando corra el pipeline |
| `e04-oidc-error.png` | El error al crear el proveedor OIDC, con el texto completo | Enzo | **Lo antes posible** |
| `e06-dynamodb-items.png` | La tabla `pixelpaws-dev-clasificaciones` con filas | Enzo, con Gustavo en llamada | Viernes 20 |
| `e07-dashboard.png` | El dashboard `pixelpaws-dev-pipeline` con datos | Gustavo | Sábado 21 |
| `e08-alarma-dlq.png` | La alarma `pixelpaws-dev-dlq-con-mensajes` en ALARM | Gustavo | Sábado 21 |
| `e09-mail-alarma.png` | El mail de AWS Notifications de la alarma | Gustavo | Sábado 21 |
| `e10-facturacion.png` | El costo real en Billing | Gustavo | Domingo 22 |
| `e11-presupuesto.png` | El presupuesto `pixelpaws-dev-presupuesto` en Budgets | Gustavo | Domingo 22 |
| `e12-calculadora.png` | La proyección cargada en calculator.aws, más el link | Gustavo | Domingo 22 |
| `e13-destroy.png` | El workflow `destroy` en verde, con "Recursos restantes" | Enzo | Lunes 23 y defensa |
| `e14-estado-vacio.png` | La cuenta sin recursos de pixelpaws | Enzo | 25/11 |
| `e14-facturacion-final.png` | La facturación del mes | Enzo | 25/11 |
| `e15-menor-privilegio.png` | La función intentando algo que no tiene permitido, y el error | Enzo | Sábado 21 |
| `e16-plan-sin-cambios.png` | Un segundo `plan` que dice "No changes" | Enzo | Cuando corra el pipeline |

**Al capturar:** que no se vean claves, contraseñas, tokens ni mails personales. El número de
cuenta de AWS no es secreto, pero si se puede, mejor taparlo.
