"""
PixelPaws Pets - funcion clasificadora.

Disparada por un evento ObjectCreated del bucket, bajo el prefijo uploads/.
Clasifica la imagen con Amazon Rekognition DetectLabels y guarda el resultado
en DynamoDB. Opcionalmente copia la foto a clasificadas/<especie>/.

Invocacion asincronica: los fallos van a la DLQ configurada en el
aws_lambda_function_event_invoke_config, no en el trigger.
"""

import json
import logging
import os
import urllib.parse
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

log = logging.getLogger()
log.setLevel(os.environ.get("NIVEL_LOG", "INFO"))

TABLA = os.environ["TABLA_DYNAMODB"]
PREFIJO_SALIDA = os.environ.get("PREFIJO_SALIDA", "clasificadas/")
MIN_CONFIANZA = float(os.environ.get("MIN_CONFIANZA", "70"))
MAX_ETIQUETAS = int(os.environ.get("MAX_ETIQUETAS", "10"))
MOVER = os.environ.get("MOVER_CLASIFICADAS", "false").lower() == "true"

rekognition = boto3.client("rekognition")
s3 = boto3.client("s3")
tabla = boto3.resource("dynamodb").Table(TABLA)

# Mapa de etiqueta de Rekognition a carpeta de salida. El extra de la consigna
# pide /perros y /gatos.
ESPECIES = {"Dog": "perros", "Cat": "gatos"}


def handler(event, context):
    """Punto de entrada. Un evento de S3 puede traer varios registros."""
    procesados, salteados, errores = 0, 0, 0

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        # Las claves llegan URL-encoded: "mi foto.jpg" viene como "mi+foto.jpg".
        clave = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        try:
            if _ya_clasificado(clave):
                log.info("Ya clasificado, se saltea: %s", clave)
                salteados += 1
                continue
            _procesar(bucket, clave)
            procesados += 1
        except Exception:
            # Se relanza para que Lambda reintente y, al agotar reintentos,
            # el evento termine en la DLQ. No se silencia nunca.
            errores += 1
            log.exception("Fallo procesando %s/%s", bucket, clave)
            raise

    resultado = {"procesados": procesados, "salteados": salteados, "errores": errores}
    log.info("Resumen: %s", json.dumps(resultado))
    return resultado


def _ya_clasificado(clave):
    """Deduplicacion: evita pagar Rekognition dos veces por el mismo archivo.

    Es la medida de ahorro numero uno de la nota de FinOps: a escala, el 95%
    del costo es la API de vision.
    """
    try:
        respuesta = tabla.get_item(Key={"archivo": clave}, ProjectionExpression="archivo")
        return "Item" in respuesta
    except ClientError:
        # Si la consulta falla no se bloquea el procesamiento: se reclasifica.
        log.warning("No se pudo verificar duplicado de %s", clave, exc_info=True)
        return False


def _procesar(bucket, clave):
    respuesta = rekognition.detect_labels(
        Image={"S3Object": {"Bucket": bucket, "Name": clave}},
        MaxLabels=MAX_ETIQUETAS,
        MinConfidence=MIN_CONFIANZA,
    )

    etiquetas = respuesta.get("Labels", [])
    if not etiquetas:
        raise ValueError("Rekognition no devolvio etiquetas sobre el umbral de confianza")

    nombre, confianza = _principal(etiquetas)
    especie = ESPECIES.get(nombre)

    item = {
        "archivo": clave,
        "etiqueta": nombre,
        # DynamoDB no acepta float: hay que usar Decimal sobre el str.
        "confianza": Decimal(str(round(confianza, 2))),
        "fecha": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "etiquetas": [
            {"nombre": e["Name"], "confianza": Decimal(str(round(e["Confidence"], 2)))}
            for e in etiquetas
        ],
        "especie": especie or "sin_clasificar",
        "bucket": bucket,
    }
    tabla.put_item(Item=item)
    log.info("Guardado %s -> %s (%.2f%%)", clave, nombre, confianza)

    if MOVER and especie:
        _copiar(bucket, clave, especie)


def _principal(etiquetas):
    """Devuelve (nombre, confianza) de la etiqueta que se guarda como principal.

    Rekognition suele dar la misma confianza a Animal, Mammal, Canine y Dog, y
    un max() simple se queda con la primera del empate: todas las fotos dirian
    "Animal". Por eso, si alguna etiqueta (o uno de sus alias) es una especie
    de ESPECIES, gana esa, con su nombre de especie. Si hay perro y gato en la
    misma foto, gana el de mayor confianza. Si no hay especie, la de mayor
    confianza, como antes.
    """
    con_especie = [(_nombre_especie(e), e["Confidence"]) for e in etiquetas]
    con_especie = [(n, c) for n, c in con_especie if n]
    if con_especie:
        return max(con_especie, key=lambda par: par[1])
    mayor = max(etiquetas, key=lambda e: e["Confidence"])
    return mayor["Name"], mayor["Confidence"]


def _nombre_especie(etiqueta):
    """'Dog' o 'Cat' si la etiqueta o alguno de sus alias es una especie, si no None."""
    nombres = [etiqueta["Name"]] + [a["Name"] for a in etiqueta.get("Aliases", [])]
    for nombre in nombres:
        if nombre in ESPECIES:
            return nombre
    return None


def _copiar(bucket, clave, especie):
    """Copia la foto a clasificadas/<especie>/.

    CUIDADO: el notification del bucket filtra por el prefijo uploads/. Si ese
    filtro se quita, esta escritura vuelve a disparar la funcion en loop y cada
    iteracion es una llamada paga a Rekognition. Es el unico riesgo real de
    factura del proyecto.
    """
    destino = PREFIJO_SALIDA + especie + "/" + os.path.basename(clave)
    s3.copy_object(
        Bucket=bucket,
        Key=destino,
        CopySource={"Bucket": bucket, "Key": clave},
        MetadataDirective="COPY",
    )
    log.info("Copiada %s -> %s", clave, destino)
