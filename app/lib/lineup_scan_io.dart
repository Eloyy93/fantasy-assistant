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
///
/// LaLiga Fantasy y Biwenger acortan los nombres que no caben en la
/// etiqueta bajo la foto — a veces con puntos suspensivos visibles
/// ("Diego Co...", "Rubén G..."), a veces sin ellos ("A. Alti" por
/// "Altimira"). En líneas de dos o más palabras, la ÚLTIMA se trata
/// siempre como un PREFIJO en vez de exigir que sea una palabra
/// completa — una palabra completa también "empieza por sí misma", así
/// que esto cubre el caso truncado sin perder precisión en el caso
/// normal.
List<CandidatoEscaneado> emparejarJugadores(List<String> lineasTexto, List<Player> jugadores) {
  // Palabras del nombre (>=3 letras) de cada jugador, precalculadas una
  // sola vez.
  final palabrasPorJugador = <String, List<String>>{
    for (final j in jugadores) j.id: _normalizar(j.nombre).split(' ').where((p) => p.length >= 3).toList(),
  };

  final candidatos = <String, CandidatoEscaneado>{};

  for (final lineaOriginal in lineasTexto) {
    final normalizada = _normalizar(_quitarPuntosSuspensivos(lineaOriginal));
    if (normalizada.length < 3) continue;

    final todasLasPalabras = normalizada.split(' ').where((p) => p.isNotEmpty).toList();
    if (todasLasPalabras.isEmpty) continue;

    // Con una sola palabra en la línea, se exige que sea una palabra
    // COMPLETA del nombre (ej. "Pedri", "Suazo") — con una sola palabra
    // no hay ancla de apoyo, así que tratarla como prefijo sería
    // demasiado débil (colaría cualquier nombre que empezara por esas
    // letras). Con dos o más palabras, la ÚLTIMA se trata siempre como
    // PREFIJO en vez de palabra completa — cubre tanto el truncamiento
    // visible ("Diego Co...") como las abreviaturas sin puntos
    // suspensivos ("A. Alti" por "Altimira"); una palabra completa
    // también "empieza por sí misma", así que esto no pierde precisión
    // en los casos donde la línea SÍ viene completa.
    Set<String> palabrasCompletas;
    String? prefijo;
    if (todasLasPalabras.length == 1) {
      palabrasCompletas = todasLasPalabras.where((p) => p.length >= 4).toSet();
      prefijo = null;
    } else {
      final palabras = List<String>.from(todasLasPalabras);
      prefijo = palabras.removeLast();
      palabrasCompletas = palabras.where((p) => p.length >= 4).toSet();
    }

    final compatibles = _buscarCompatibles(palabrasCompletas, prefijo, jugadores, palabrasPorJugador);
    if (compatibles.isEmpty) continue;

    final cubiertas = palabrasCompletas.length + (prefijo != null ? 1 : 0);
    for (final jugador in compatibles) {
      final palabrasNombre = palabrasPorJugador[jugador.id]!;
      final nombreCompletoNormalizado = palabrasNombre.join(' ');
      var puntuacion = normalizada == nombreCompletoNormalizado
          ? 1.0
          : (0.5 + 0.5 * (cubiertas / palabrasNombre.length)).clamp(0.0, 1.0);

      // Si esta misma línea encaja con MÁS DE UN jugador del mercado, no
      // hay forma de saber a cuál se refiere la captura — se mantienen
      // todos en la lista pero con confianza reducida (por debajo del
      // umbral de preselección) para que el usuario elija a mano, en vez
      // de proponerlos ya marcados o hacerlos desaparecer.
      if (compatibles.length > 1) puntuacion = puntuacion.clamp(0.0, 0.65);

      final existente = candidatos[jugador.id];
      if (existente == null || puntuacion > existente.confianza) {
        candidatos[jugador.id] = CandidatoEscaneado(jugador: jugador, confianza: puntuacion);
      }
    }
  }

  final lista = candidatos.values.toList()..sort((a, b) => b.confianza.compareTo(a.confianza));
  return lista;
}

/// Jugadores del mercado compatibles con las palabras reconocidas: cada
/// palabra de [palabrasCompletas] tiene que ser una palabra real de su
/// nombre, y si hay [prefijo], el nombre tiene que tener alguna palabra
/// que empiece por él.
List<Player> _buscarCompatibles(
  Set<String> palabrasCompletas,
  String? prefijo,
  List<Player> jugadores,
  Map<String, List<String>> palabrasPorJugador,
) {
  if (palabrasCompletas.isEmpty && (prefijo == null || prefijo.length < 3)) return const [];
  final compatibles = <Player>[];
  for (final jugador in jugadores) {
    final palabrasNombre = palabrasPorJugador[jugador.id]!;
    if (palabrasNombre.isEmpty) continue;
    final nombreSet = palabrasNombre.toSet();
    if (!palabrasCompletas.every(nombreSet.contains)) continue;
    if (prefijo != null && !palabrasNombre.any((w) => w.startsWith(prefijo))) continue;
    compatibles.add(jugador);
  }
  return compatibles;
}

String _quitarPuntosSuspensivos(String texto) {
  var t = texto.trim();
  if (t.endsWith('...')) return t.substring(0, t.length - 3);
  if (t.endsWith('…')) return t.substring(0, t.length - 1);
  return t;
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
