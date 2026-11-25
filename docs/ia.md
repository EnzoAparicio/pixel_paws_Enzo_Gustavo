# Uso de inteligencia artificial

## Herramientas

| Herramienta | Para qué |
|---|---|
| **Claude (Anthropic), vía Claude Code** | Primer borrador del Terraform y de la función Lambda, redacción de documentación y diagnóstico de errores |
| **Excalidraw** | Los diagramas de [`diagramas/`](diagramas/), dibujados a mano |
| **Checkov y tflint** | Análisis estático del Terraform en el pipeline. No son IA, pero forman parte del circuito de validación |

## Lineamientos

1. **Nada se da por cierto hasta que lo responde la cuenta.** Lo que afirma la IA es una
   hipótesis: se confirma ejecutando el comando.
2. **El código entra solo si lo podemos explicar.** Si no lo sabríamos defender, no va.
3. **El alcance lo define la consigna.** Las herramientas tienden a agregar de más.
4. **Toda supresión de Checkov se justifica por escrito** en [`seguridad.md`](seguridad.md).
5. **Nada de credenciales en los prompts.**

## Ejemplos de uso

Generación de infraestructura:

> "Armá el módulo de observabilidad: dashboard de CloudWatch con invocaciones, errores y
> duración de la Lambda, más la profundidad de la DLQ. Alarma sobre mensajes visibles en la
> cola."

Diagnóstico, que fue donde más sirvió. Se pegaba la salida del error y se pedía un diagnóstico
ordenado por probabilidad con comandos para verificar cada hipótesis:

> "Al subir una foto al bucket no aparece nada en DynamoDB y la función no registra ninguna
> invocación. El apply terminó bien hace dos minutos."

La causa resultó ser que la notificación de un bucket recién creado tarda entre 3 y 6 minutos
en empezar a entregar eventos. No estaba en ninguna guía que hubiéramos leído y hoy es una
advertencia explícita en el [runbook](runbook.md).

## Validación

Todo lo técnico se verificó contra la cuenta: `terraform validate`, `tflint` y `plan` en cada
PR, Checkov con 57 controles en verde, el lote de 20 fotos con 20 aciertos, el camino de error
disparado a propósito y un ciclo completo de `destroy` y `apply`. **Ningún número de este
repositorio salió de una estimación de la IA**: todos están medidos.

También hubo errores, y el más caro fue nuestro. Un intento fallido de crear el proveedor OIDC,
cuyo mensaje de error nadie guardó, nos llevó a concluir que la cuenta lo bloqueaba. La
explicación era verosímil y la dimos por buena sin probarla. Sobre esa premisa rediseñamos el
pipeline entero con credenciales temporales. Una semana después lo probamos y **el proveedor se
creó sin error**: la premisa era falsa y hubo que deshacer el rediseño. De ahí sale el primer
lineamiento.

**La conclusión: la IA sirve para proponer y para explicar, no para confirmar. Lo que confirma
es la consola.**
