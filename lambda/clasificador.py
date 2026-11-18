"""PixelPaws Pets: clasifica la foto subida a uploads/ con Rekognition y la guarda en DynamoDB."""

import json
import logging
import os
import urllib.parse
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

log = logging.getLogger()
log.setLevel(logging.INFO)

TABLA = os.environ["TABLA_DYNAMODB"]
MIN_CONFIANZA = 70  # debajo de esto las etiquetas de Rekognition son ruido
MAX_ETIQUETAS = 10
ESPECIES = {"Dog", "Cat"}

rekognition = boto3.client("rekognition")
tabla = boto3.resource("dynamodb").Table(TABLA)


def handler(event, context):
    """Punto de entrada. Un evento de S3 puede traer varios registros."""
    procesados, salteados = 0, 0

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
            # Se relanza para que Lambda reintente y, si sigue fallando, el evento vaya a la DLQ.
            log.exception("Fallo procesando %s/%s", bucket, clave)
            raise

    resultado = {"procesados": procesados, "salteados": salteados}
    log.info("Resumen: %s", json.dumps(resultado))
    return resultado


def _ya_clasificado(clave):
    """Deduplicacion: no paga Rekognition dos veces por el mismo archivo."""
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

    tabla.put_item(
        Item={
            "archivo": clave,
            "etiqueta": nombre,
            # DynamoDB no acepta float: hay que usar Decimal sobre el str.
            "confianza": Decimal(str(round(confianza, 2))),
            "fecha": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
    )
    log.info("Guardado %s -> %s (%.2f%%)", clave, nombre, confianza)


def _principal(etiquetas):
    """Etiqueta principal: Dog o Cat si aparecen (Rekognition empata con Animal); si no, la de mayor confianza."""
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
