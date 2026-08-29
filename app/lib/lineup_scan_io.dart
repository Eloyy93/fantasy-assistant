import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'api_client.dart';

/// Un jugador de la fuente que el reconocimiento de texto encontró
/// mencionado en la captura, con una puntuación de qué tan segura es la
/// coincidencia — el texto reconocido de una interfaz tan visual (fotos,
/// escudos, precios superpuestos al nombre) nunca es perfecto, así que
/// esto es una propuesta para que el usuario confirme, no un resultado
/// definitivo.
class CandidatoEscaneado {
  final Player jugador;
  final double confianza; // 0..1

  CandidatoEscaneado({required this.jugador, required this.confianza});
}

/// Extrae todo el texto de la imagen con reconocimiento en el propio
/// dispositivo (ML Kit, gratis, sin conexión) — cada bloque reconocido es
/// una línea de texto suelta, sin ninguna estructura ni posición fiable
/// más allá de "estaba en algún sitio de la imagen".
Future<List<String>> reconocerTexto(String rutaImagen) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final resultado = await recognizer.processImage(InputImage.fromFile(File(rutaImagen)));
    return resultado.blocks.expand((b) => b.lines).map((l) => l.text).toList();
  } finally {
    await recognizer.close();
  }
}

/// Compara cada línea de texto reconocida contra el nombre de cada
/// jugador de la fuente y se queda con los que superan el umbral de
/// confianza — igual que la búsqueda del buscador, comparando sin
/// acentos ni mayúsculas, pero aquí necesitamos además una puntuación
/// (no solo "contiene o no contiene") para poder ordenar por fiabilidad
/// y dejar fuera coincidencias demasiado débiles (ej. una sola letra
/// suelta que el OCR haya confundido).
List<CandidatoEscaneado> emparejarJugadores(List<String> lineasTexto, List<Player> jugadores) {
  final candidatos = <String, CandidatoEscaneado>{};

  for (final linea in lineasTexto) {
    final normalizada = _normalizar(linea);
    if (normalizada.length < 3) continue;

    for (final jugador in jugadores) {
      final nombreNormalizado = _normalizar(jugador.nombre);
      final puntuacion = _puntuarCoincidencia(normalizada, nombreNormalizado);
      if (puntuacion < 0.6) continue;

      final existente = candidatos[jugador.id];
      if (existente == null || puntuacion > existente.confianza) {
        candidatos[jugador.id] = CandidatoEscaneado(jugador: jugador, confianza: puntuacion);
      }
    }
  }

  final lista = candidatos.values.toList()..sort((a, b) => b.confianza.compareTo(a.confianza));
  return lista;
}

String _normalizar(String texto) {
  const conAcento = 'áéíóúüñÁÉÍÓÚÜÑ';
  const sinAcento = 'aeiouunAEIOUUN';
  var resultado = texto.toLowerCase();
  for (var i = 0; i < conAcento.length; i++) {
    resultado = resultado.replaceAll(conAcento[i], sinAcento[i].toLowerCase());
  }
  return resultado.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 0..1 — coincidencia exacta de la línea completa puntúa más que un
/// coincidencia parcial de una sola palabra encontrada dentro de un
/// nombre completo más largo, que a su vez puntúa más que no encontrar
/// nada.
double _puntuarCoincidencia(String lineaNormalizada, String nombreNormalizado) {
  if (lineaNormalizada == nombreNormalizado) return 1.0;

  // Ojo: NO asumir que lo que hay que buscar es el apellido (última
  // palabra) — Biwenger y LaLiga Fantasy muestran bajo la foto lo que sea
  // más corto/común, que muchas veces es el nombre de pila o un apodo
  // (ej. "Pedri", "Fermín" en vez de "Fermín López"), no necesariamente
  // el apellido.
  final palabrasNombre = nombreNormalizado.split(' ').where((p) => p.length >= 3).toSet();
  if (palabrasNombre.isEmpty) return 0;

  // Palabras de la línea con umbral más alto (4, no 3): el texto
  // reconocido de una interfaz tan visual trae más ruido que el nombre
  // real del jugador, y una palabra de 3 letras suelta tiene bastante
  // más probabilidad de ser basura del OCR que de ser parte real de un
  // nombre.
  final palabrasLinea = lineaNormalizada.split(' ').where((p) => p.length >= 4).toList();
  if (palabrasLinea.isEmpty) return 0;

  final coincidencias = palabrasLinea.where(palabrasNombre.contains).length;
  if (coincidencias == 0) return 0;

  // Cuanto más de la línea reconocida está cubierta por el nombre, y
  // cuanto más del nombre está cubierto por la línea, más fiable la
  // coincidencia — así "Fermin" contra "Fermín López" puntúa alto (cubre
  // toda la línea) sin necesitar el apellido completo.
  final ratioLinea = coincidencias / palabrasLinea.length;
  final ratioNombre = coincidencias / palabrasNombre.length;
  return (0.5 * ratioLinea + 0.5 * ratioNombre).clamp(0.0, 1.0);
}
