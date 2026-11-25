# Decisión 01 - cuenta y entorno

> Esta nota es un entregable en sí misma. El criterio de Arquitectura (30%) evalúa
> "decisiones justificadas". Una limitación del entorno reconocida y mitigada por diseño
> puntúa mejor que una limitación silenciada.

## Decisión

**Cuenta AWS propia (plan Free), región `us-east-2` (Ohio).** Equipo Enzo Aparicio y Gustavo Gonzalez.

### Punto de partida real

Ninguno de los labs del semestre usó una cuenta AWS real. Verificado en las propias consignas:

| Lab                | Plataforma                            | URL en la consigna                                    |
| ------------------ | ------------------------------------- | ----------------------------------------------------- |
| 01, 02 IAM, 03, 04 | AWS Skill Builder (simulación guiada) | `skillbuilder.aws/learn/...`                          |
| 05                 | Google Cloud Skills Boost             | `skills.google`                                       |
| 06 (IaC)           | Primera que exige cuenta real         | repo base `github.com/academialabs/ucu-pde-cloud-iac` |

Skill Builder no entrega credenciales de CLI ni consola real, así que **no hay cuenta previa que
reutilizar**. La decisión se toma desde cero.

### Alternativas

| Opción                           | Veredicto                                                                                                                                                                                                                        |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Cuenta AWS propia, plan Free** | **Elegida.** USD 100 de crédito al alta (más hasta USD 100 por actividades), 6 meses, sin posibilidad de generar cargos en el plan Free. IAM completo, OIDC y AWS Budgets disponibles. Alta en 15 minutos, sin depender de nadie |
| AWS Academy Learner Lab          | Contingencia. Todos los servicios de PixelPaws están habilitados, pero IAM no permite crear roles, no hay OIDC y no existe AWS Budgets. Además la inscripción depende de que el docente invite, y no hay invitación              |
| Azure for Students               | USD 100 sin tarjeta y OIDC de primera clase, pero obliga a aprender Entra ID, Event Grid y Cosmos DB desde cero con una semana disponible                                                                                        |
| Skill Builder                    | Simulación. No sirve para Terraform                                                                                                                                                                                              |

El factor decisivo fue el tiempo, pero al revés de lo que parecía: con 7 días, lo que no se puede
pagar es esperar la respuesta de un mail. La cuenta propia además elimina las tres brechas de
rúbrica descritas abajo.

Salvedades asumidas: AWS suele pedir un medio de pago para verificar identidad (cargo temporal de
USD 1 que se devuelve), y el plan Free excluye algunos servicios de alto consumo sin listarlos.
Rekognition no es uno de ellos, pero la prueba de humo del final sigue siendo obligatoria.

### El episodio OIDC: una conclusión apurada que estuvo mal una semana

Vale la pena dejarlo escrito porque es el error de método más caro que cometimos.

El 18/11, el primer intento de crear el proveedor OIDC de GitHub falló. Sin guardar el mensaje
de error, concluimos que la cuenta lo bloqueaba y le buscamos una explicación: la cuenta del plan
Free vive dentro de una organización administrada por AWS, con una política de control de
servicios (SCP) que prevalece sobre los permisos de la cuenta. Como esa política efectivamente
restringe otras cosas (solo habilita `us-east-2` y niega las contraseñas de consola para usuarios
IAM), la explicación cerraba.

Sobre esa conclusión rediseñamos el pipeline entero: credenciales temporales de 12 horas
generadas a mano, un usuario IAM emisor, un rol intermedio y un script para renovarlas.

**El 25/11 lo volvimos a probar y el proveedor se creó sin ningún error.** La SCP no bloquea
OIDC. La conclusión era falsa, y el rediseño completo del pipeline se hizo sobre una premisa que
nunca se verificó.

Tres cosas que quedan de esto:

1. **Un error sin guardar no es evidencia.** Nadie copió el mensaje del 18/11, así que durante
   una semana la documentación afirmó una causa que nadie podía comprobar.
2. **Una explicación que encaja no es una explicación verificada.** La SCP existía y restringía
   otras cosas, y eso hizo verosímil la hipótesis. Verosímil no es verdadero.
3. **La verificación costaba dos minutos.** El rediseño del pipeline costó varios días.

Cómo quedó: el pipeline usa OIDC, con `enable_oidc = true`. El camino de las credenciales
temporales se conserva en `scripts/credenciales-ci.sh` como respaldo para una cuenta donde OIDC
no esté disponible.


## Verificación de servicios

Contrastado contra _AWS Academy Learner Lab - Foundation Services_ (documento oficial de AWS).
**Los siete servicios de PixelPaws están habilitados:**

| Pieza de PixelPaws            | Servicio           | ¿Habilitado?            |
| ----------------------------- | ------------------ | ----------------------- |
| Bucket de entrada y de salida | Amazon S3          | Sí                      |
| Función clasificadora         | AWS Lambda         | Sí                      |
| Visión preentrenada           | Amazon Rekognition | Sí, sin sublimitaciones |
| Tabla de etiquetas            | Amazon DynamoDB    | Sí                      |
| Cola de errores (DLQ)         | Amazon SQS         | Sí                      |
| Dashboard y alarmas           | Amazon CloudWatch  | Sí                      |
| Notificación de alarma        | Amazon SNS         | Sí                      |

Región: el documento de Learner Lab limita todo a `us-east-1` y `us-west-2`. En la cuenta
propia esa restricción no aplica. La región efectiva es **`us-east-2` (Ohio)**, porque el alta
quedó anclada ahí y la consola no permite cambiarla. No tiene costo: Ohio está en la misma
franja de precios que Virginia para los siete servicios del proyecto, y tiene mejor huella de
carbono publicada. La prueba de humo de Rekognition se corrió en `us-east-2` y funcionó.

## Las tres brechas reales

Cita textual del documento oficial:

> AWS Identity and Access Management (IAM): Extremely limited access. You cannot create
> users or groups. **You cannot create roles**, except that you can create service-linked roles.

De ahí salen tres cosas que el entorno no puede ejecutar:

1. **Rol de ejecución propio para la Lambda.** No se puede crear. Hay que usar `LabRole`,
   un rol preexistente y amplio, que es lo contrario del menor privilegio.
2. **Proveedor de identidad OIDC para GitHub Actions.** Es un recurso de IAM, así que está
   bloqueado. La consigna 2.4 dice "prohibido guardar claves de acceso de larga duración"
   y la rúbrica pide "OIDC sin claves estáticas".
3. **AWS Budgets.** No figura en la lista de servicios habilitados, y tampoco hay consola
   de facturación. El presupuesto de USD 10 con alertas 50/80/100% no se puede aplicar.

### Atenuante sobre el punto 2

Las credenciales de Learner Lab son **credenciales temporales de sesión**: incluyen
`AWS_SESSION_TOKEN` y caducan al cerrar la sesión del lab. Literalmente **no son claves de
larga duración**, que es lo que la consigna prohíbe. Y el propio lab 06 del docente prescribe
exactamente este patrón para quien use Academy, con esta nota al pie:

> Claves estáticas: solo para este laboratorio. En producción se usa OIDC (federación):
> credenciales temporales por ejecución. **Queda como desafío.**

La pregunta de cierre 4 del lab 06 es "¿qué riesgos tienen las claves estáticas que usaste y
cómo los elimina OIDC?". O sea que el docente sabe que en Academy no se puede y lo trata como
tema teórico. El costo de esta brecha es parcial, no total.

## Cómo quedó en el código

Con la cuenta propia confirmada, el respaldo para Learner Lab dejó de tener sentido y se sacó:
ya no existen las banderas `crear_iam_propio` ni `enable_budget`. El rol de menor privilegio de
la función y el presupuesto se crean siempre.

Queda una sola bandera, `enable_oidc`, en `true`: el pipeline se autentica con OIDC y no hay
ninguna clave de AWS guardada en GitHub. Se deja como bandera y no como código fijo porque hay
entornos, como el propio Learner Lab, donde crear el proveedor no está permitido; en ese caso se
pone en `false` y se vuelve al camino de respaldo. El detalle de cómo funciona está en
`docs/seguridad.md`.

## Impacto estimado en la rúbrica

| Criterio              | Peso | Estado con Learner Lab                                                                  |
| --------------------- | ---- | --------------------------------------------------------------------------------------- |
| Arquitectura y diseño | 30%  | Intacto. Esta nota suma, no resta                                                       |
| Terraform             | 25%  | Intacto                                                                                 |
| CI/CD                 | 10%  | Parcial. Se pierde el OIDC aplicado, se conserva plan en PR, apply controlado y destroy |
| Seguridad e IAM       | 10%  | Parcial. La matriz IAM se documenta y se codifica, pero corre con LabRole               |
| Observabilidad        | 10%  | Intacto                                                                                 |
| FinOps                | 10%  | Parcial. Sin AWS Budgets aplicado. Se conserva costo real vs estimado y proyección      |
| Presentación          | 5%   | Intacto                                                                                 |

Exposición realista: entre 8 y 15 puntos, no 30. Y buena parte se recupera con el `plan`
de arriba más el párrafo de limitaciones en el README.

## Operativa del entorno

- Las credenciales caducan al cerrar la sesión del lab. Hay que **repegar los tres secretos**
  (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) en GitHub antes de cada
  corrida del pipeline. El día de la defensa, repegarlos primero.
- El bucket del estado se crea a mano una vez (problema de bootstrap), como en el lab 06.
- Backend `s3` con `use_lockfile = true`. No hace falta tabla DynamoDB de lock.
- `LabRole` hay que obtener su ARN con `aws iam list-roles --query "Roles[?RoleName=='LabRole'].Arn"`.
