"""Tests de la funcion clasificadora, sin AWS real.

Rekognition, S3 y DynamoDB se reemplazan por mocks, asi que no hacen falta
credenciales ni red. Si boto3 no esta instalado (como en una PC sin el SDK),
se inyecta un boto3 falso antes de importar la funcion.

Correr desde la raiz del repo (no necesita nada instalado):

    python -m unittest discover -s lambda/tests -v

Tambien funcionan con pytest si esta instalado: pytest lambda/tests
"""

import importlib.util
import os
import sys
import types
import unittest
from decimal import Decimal
from pathlib import Path
from unittest import mock

RUTA_FUNCION = Path(__file__).resolve().parent.parent / "clasificador.py"


def _instalar_boto3_falso():
    """Registra modulos boto3 y botocore minimos si no estan instalados."""
    try:
        import boto3  # noqa: F401
        import botocore.exceptions  # noqa: F401
        return
    except ImportError:
        pass

    class ClientError(Exception):
        def __init__(self, error_response, operation_name):
            super().__init__(f"{operation_name}: {error_response}")
            self.response = error_response
            self.operation_name = operation_name

    boto3 = types.ModuleType("boto3")
    boto3.client = mock.MagicMock(name="boto3.client")
    boto3.resource = mock.MagicMock(name="boto3.resource")
    botocore = types.ModuleType("botocore")
    excepciones = types.ModuleType("botocore.exceptions")
    excepciones.ClientError = ClientError
    botocore.exceptions = excepciones
    sys.modules.update({"boto3": boto3, "botocore": botocore, "botocore.exceptions": excepciones})


def _cargar_funcion():
    """Importa clasificador.py con variables de entorno de prueba.

    La funcion crea los clientes de AWS al importarse: se parchean boto3.client
    y boto3.resource para que nunca intente conectarse.
    """
    _instalar_boto3_falso()
    import boto3

    entorno = {
        "TABLA_DYNAMODB": "pixelpaws-clasificaciones-test",
        "MIN_CONFIANZA": "70",
        "MAX_ETIQUETAS": "10",
        "MOVER_CLASIFICADAS": "false",
        "AWS_DEFAULT_REGION": "us-east-2",
    }
    with mock.patch.dict(os.environ, entorno), \
            mock.patch.object(boto3, "client", mock.MagicMock()), \
            mock.patch.object(boto3, "resource", mock.MagicMock()):
        spec = importlib.util.spec_from_file_location("clasificador", RUTA_FUNCION)
        modulo = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(modulo)
    return modulo


clasificador = _cargar_funcion()


def evento_s3(*claves, bucket="pixelpaws-fotos-test"):
    """Arma un evento ObjectCreated de S3 como el que recibe la Lambda."""
    return {
        "Records": [
            {"s3": {"bucket": {"name": bucket}, "object": {"key": clave}}}
            for clave in claves
        ]
    }


def etiqueta(nombre, confianza, alias=()):
    return {"Name": nombre, "Confidence": confianza, "Aliases": [{"Name": a} for a in alias]}


def hay_float(valor):
    """True si en la estructura queda algun float (DynamoDB los rechaza)."""
    if isinstance(valor, float):
        return True
    if isinstance(valor, dict):
        return any(hay_float(v) for v in valor.values())
    if isinstance(valor, (list, tuple)):
        return any(hay_float(v) for v in valor)
    return False


class BaseClasificador(unittest.TestCase):
    """Reemplaza los tres clientes de AWS por mocks nuevos en cada test."""

    def setUp(self):
        self.rekognition = mock.MagicMock(name="rekognition")
        self.s3 = mock.MagicMock(name="s3")
        self.tabla = mock.MagicMock(name="tabla")
        # Por defecto la foto no esta en la tabla todavia.
        self.tabla.get_item.return_value = {}
        for nombre, valor in (("rekognition", self.rekognition), ("s3", self.s3), ("tabla", self.tabla)):
            parche = mock.patch.object(clasificador, nombre, valor)
            parche.start()
            self.addCleanup(parche.stop)

    def responder_etiquetas(self, *etiquetas):
        self.rekognition.detect_labels.return_value = {"Labels": list(etiquetas)}

    def item_guardado(self):
        self.tabla.put_item.assert_called_once()
        return self.tabla.put_item.call_args.kwargs["Item"]


class CaminoFeliz(BaseClasificador):

    def test_perro_se_guarda_con_la_etiqueta_de_mayor_confianza(self):
        self.responder_etiquetas(
            etiqueta("Animal", 95.5),
            etiqueta("Dog", 98.123),
            etiqueta("Pet", 90.0),
        )

        resultado = clasificador.handler(evento_s3("uploads/lote/perro01.jpg"), None)

        self.assertEqual(resultado, {"procesados": 1, "salteados": 0, "errores": 0})
        item = self.item_guardado()
        self.assertEqual(item["archivo"], "uploads/lote/perro01.jpg")
        self.assertEqual(item["etiqueta"], "Dog")
        self.assertEqual(item["especie"], "perros")
        self.assertEqual(item["bucket"], "pixelpaws-fotos-test")
        self.assertEqual(len(item["etiquetas"]), 3)

    def test_confianza_redondeada_a_dos_decimales_y_sin_float(self):
        self.responder_etiquetas(etiqueta("Cat", 97.12345))

        clasificador.handler(evento_s3("uploads/gato.jpg"), None)

        item = self.item_guardado()
        self.assertEqual(item["confianza"], Decimal("97.12"))
        self.assertIsInstance(item["confianza"], Decimal)
        self.assertFalse(hay_float(item), "DynamoDB no acepta float: todo numero va como Decimal")

    def test_fecha_en_utc_formato_iso(self):
        self.responder_etiquetas(etiqueta("Cat", 99.0))

        clasificador.handler(evento_s3("uploads/gato.jpg"), None)

        fecha = self.item_guardado()["fecha"]
        self.assertRegex(fecha, r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+00:00$")

    def test_rekognition_recibe_bucket_clave_y_umbrales(self):
        self.responder_etiquetas(etiqueta("Dog", 99.0))

        clasificador.handler(evento_s3("uploads/perro.jpg", bucket="mi-bucket"), None)

        self.rekognition.detect_labels.assert_called_once_with(
            Image={"S3Object": {"Bucket": "mi-bucket", "Name": "uploads/perro.jpg"}},
            MaxLabels=10,
            MinConfidence=70.0,
        )

    def test_clave_url_encoded_se_decodifica(self):
        # S3 manda "mi foto (1).jpg" como "mi+foto+%281%29.jpg".
        self.responder_etiquetas(etiqueta("Dog", 99.0))

        clasificador.handler(evento_s3("uploads/mi+foto+%281%29.jpg"), None)

        nombre = self.rekognition.detect_labels.call_args.kwargs["Image"]["S3Object"]["Name"]
        self.assertEqual(nombre, "uploads/mi foto (1).jpg")
        self.assertEqual(self.item_guardado()["archivo"], "uploads/mi foto (1).jpg")

    def test_varios_registros_en_un_evento(self):
        self.responder_etiquetas(etiqueta("Dog", 99.0))

        resultado = clasificador.handler(evento_s3("uploads/a.jpg", "uploads/b.jpg"), None)

        self.assertEqual(resultado["procesados"], 2)
        self.assertEqual(self.tabla.put_item.call_count, 2)

    def test_evento_vacio_no_hace_nada(self):
        resultado = clasificador.handler({}, None)

        self.assertEqual(resultado, {"procesados": 0, "salteados": 0, "errores": 0})
        self.rekognition.detect_labels.assert_not_called()


class Especie(BaseClasificador):

    def test_empate_de_rekognition_gana_la_especie(self):
        # Caso real del primer deploy: Rekognition dio 99.88% a Animal, Canine y
        # Dog, en ese orden, y un max() simple guardaba "Animal".
        self.responder_etiquetas(
            etiqueta("Animal", 99.88),
            etiqueta("Canine", 99.88),
            etiqueta("Dog", 99.88),
            etiqueta("Pet", 99.88),
            etiqueta("Mammal", 99.88),
        )

        clasificador.handler(evento_s3("uploads/perro.jpg"), None)

        item = self.item_guardado()
        self.assertEqual(item["etiqueta"], "Dog")
        self.assertEqual(item["especie"], "perros")

    def test_la_especie_gana_aunque_tenga_menos_confianza(self):
        self.responder_etiquetas(etiqueta("Animal", 99.9), etiqueta("Cat", 97.5))

        clasificador.handler(evento_s3("uploads/gato.jpg"), None)

        item = self.item_guardado()
        self.assertEqual(item["etiqueta"], "Cat")
        # La confianza guardada es la de la especie, no la de "Animal".
        self.assertEqual(item["confianza"], Decimal("97.5"))

    def test_gato_detectado_por_alias(self):
        # Ninguna etiqueta se llama "Cat", pero "Pet" lo trae como alias.
        self.responder_etiquetas(etiqueta("Pet", 96.0, alias=("Cat",)), etiqueta("Animal", 99.0))

        clasificador.handler(evento_s3("uploads/gato.jpg"), None)

        item = self.item_guardado()
        self.assertEqual(item["etiqueta"], "Cat")
        self.assertEqual(item["confianza"], Decimal("96.0"))
        self.assertEqual(item["especie"], "gatos")

    def test_perro_y_gato_en_la_misma_foto_gana_el_mas_seguro(self):
        self.responder_etiquetas(etiqueta("Dog", 91.0), etiqueta("Cat", 96.0))

        clasificador.handler(evento_s3("uploads/los-dos.jpg"), None)

        item = self.item_guardado()
        self.assertEqual(item["etiqueta"], "Cat")
        self.assertEqual(item["especie"], "gatos")

    def test_ni_perro_ni_gato_queda_sin_clasificar(self):
        self.responder_etiquetas(etiqueta("Animal", 95.0), etiqueta("Bird", 97.0))

        clasificador.handler(evento_s3("uploads/loro.jpg"), None)

        item = self.item_guardado()
        # Sin especie, la principal sigue siendo la de mayor confianza.
        self.assertEqual(item["etiqueta"], "Bird")
        self.assertEqual(item["especie"], "sin_clasificar")


class Deduplicacion(BaseClasificador):
    """La medida de ahorro numero uno de FinOps: no pagar Rekognition dos veces."""

    def test_foto_ya_clasificada_se_saltea_sin_llamar_a_rekognition(self):
        self.tabla.get_item.return_value = {"Item": {"archivo": "uploads/perro.jpg"}}

        resultado = clasificador.handler(evento_s3("uploads/perro.jpg"), None)

        self.assertEqual(resultado, {"procesados": 0, "salteados": 1, "errores": 0})
        self.rekognition.detect_labels.assert_not_called()
        self.tabla.put_item.assert_not_called()

    def test_la_consulta_de_duplicado_pide_solo_la_clave(self):
        self.responder_etiquetas(etiqueta("Dog", 99.0))

        clasificador.handler(evento_s3("uploads/perro.jpg"), None)

        self.tabla.get_item.assert_called_once_with(
            Key={"archivo": "uploads/perro.jpg"}, ProjectionExpression="archivo"
        )

    def test_si_falla_la_consulta_se_clasifica_igual(self):
        error = clasificador.ClientError(
            {"Error": {"Code": "ProvisionedThroughputExceededException", "Message": "x"}}, "GetItem"
        )
        self.tabla.get_item.side_effect = error
        self.responder_etiquetas(etiqueta("Dog", 99.0))

        with self.assertLogs(clasificador.log, level="WARNING"):
            resultado = clasificador.handler(evento_s3("uploads/perro.jpg"), None)

        self.assertEqual(resultado["procesados"], 1)
        self.tabla.put_item.assert_called_once()


class Errores(BaseClasificador):
    """Todo error se relanza para que Lambda reintente y termine en la DLQ."""

    def assert_falla_y_registra(self, tipo, clave):
        """El error se relanza y queda en el log con el nombre del archivo."""
        with self.assertLogs(clasificador.log, level="ERROR") as logs, self.assertRaises(tipo):
            clasificador.handler(evento_s3(clave), None)
        self.assertIn(clave, "\n".join(logs.output))

    def test_sin_etiquetas_sobre_el_umbral_lanza_error(self):
        self.responder_etiquetas()

        self.assert_falla_y_registra(ValueError, "uploads/borrosa.jpg")
        self.tabla.put_item.assert_not_called()

    def test_error_de_rekognition_se_propaga(self):
        # Es lo que pasa en la demo de la DLQ: un .txt renombrado a .jpg.
        self.rekognition.detect_labels.side_effect = clasificador.ClientError(
            {"Error": {"Code": "InvalidImageFormatException", "Message": "formato"}}, "DetectLabels"
        )

        self.assert_falla_y_registra(clasificador.ClientError, "uploads/roto.jpg")
        self.tabla.put_item.assert_not_called()

    def test_error_al_guardar_se_propaga(self):
        self.responder_etiquetas(etiqueta("Dog", 99.0))
        self.tabla.put_item.side_effect = RuntimeError("DynamoDB caido")

        self.assert_falla_y_registra(RuntimeError, "uploads/perro.jpg")


class MoverClasificadas(BaseClasificador):
    """El extra de la consigna: copiar a clasificadas/perros/ y clasificadas/gatos/."""

    def test_apagado_por_defecto_no_copia(self):
        self.responder_etiquetas(etiqueta("Dog", 99.0))

        clasificador.handler(evento_s3("uploads/lote/perro01.jpg"), None)

        self.s3.copy_object.assert_not_called()

    def test_prendido_copia_a_la_carpeta_de_la_especie(self):
        self.responder_etiquetas(etiqueta("Dog", 99.0))

        with mock.patch.object(clasificador, "MOVER", True):
            clasificador.handler(evento_s3("uploads/lote/perro01.jpg", bucket="b"), None)

        self.s3.copy_object.assert_called_once_with(
            Bucket="b",
            Key="clasificadas/perros/perro01.jpg",
            CopySource={"Bucket": "b", "Key": "uploads/lote/perro01.jpg"},
            MetadataDirective="COPY",
        )

    def test_la_copia_nunca_cae_en_uploads(self):
        # Si la copia cayera en uploads/ volveria a disparar la funcion en loop:
        # es el unico riesgo real de factura del proyecto.
        self.responder_etiquetas(etiqueta("Cat", 99.0))

        with mock.patch.object(clasificador, "MOVER", True):
            clasificador.handler(evento_s3("uploads/gato.jpg"), None)

        destino = self.s3.copy_object.call_args.kwargs["Key"]
        self.assertTrue(destino.startswith("clasificadas/"))
        self.assertFalse(destino.startswith("uploads/"))

    def test_prendido_pero_sin_especie_no_copia(self):
        self.responder_etiquetas(etiqueta("Bird", 99.0))

        with mock.patch.object(clasificador, "MOVER", True):
            clasificador.handler(evento_s3("uploads/loro.jpg"), None)

        self.s3.copy_object.assert_not_called()


if __name__ == "__main__":
    unittest.main()
