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
/// LaLiga Fantasy y Biwenger truncan los nombres que no caben en la
/// etiqueta bajo la foto, con puntos suspensivos: "Diego Co...", "Rubén
/// G...". La última palabra de esas líneas no es una palabra completa —
/// es un PREFIJO cortado a mitad — así que se trata de forma distinta:
/// no tiene que coincidir exacta, solo tiene que ser el principio de
/// alguna palabra del nombre.
List<CandidatoEscaneado> emparejarJugadores(List<String> lineasTexto, List<Player> jugadores) {
  // Palabras del nombre (>=3 letras) de cada jugador, precalculadas una
  // sola vez.
  final palabrasPorJugador = <String, List<String>>{
    for (final j in jugadores) j.id: _normalizar(j.nombre).split(' ').where((p) => p.length >= 3).toList(),
  };

  final candidatos = <String, CandidatoEscaneado>{};

  for (final lineaOriginal in lineasTexto) {
    final truncada = _terminaTruncada(lineaOriginal);
    final normalizada = _normalizar(_quitarPuntosSuspensivos(lineaOriginal));
    if (normalizada.length < 3) continue;

    final todasLasPalabras = normalizada.split(' ').where((p) => p.isNotEmpty).toList();
    if (todasLasPalabras.isEmpty) continue;

    // Si la línea viene truncada, la última palabra reconocida puede
    // estar cortada — se separa y se trata como prefijo. El resto tiene
    // que ser palabras completas (mínimo 4 letras, para filtrar ruido
    // del OCR de interfaces tan visuales).
    final prefijoTruncado = truncada ? todasLasPalabras.removeLast() : null;
    final palabrasCompletas = todasLasPalabras.where((p) => p.length >= 4).toSet();
    // Un prefijo cortado por sí solo, sin ninguna palabra completa que
    // sirva de ancla (ej. la línea era literalmente solo "Co..."), es
    // demasiado débil — cualquier apellido que empiece por esas letras
    // colaría. Solo se usa junto con al menos una palabra completa.
    if (palabrasCompletas.isEmpty) continue;

    // Todos los jugadores del mercado compatibles con esta línea: cada
    // palabra completa tiene que ser una palabra real de su nombre (sin
    // ninguna ajena), y si hay prefijo truncado, el nombre tiene que
    // tener alguna palabra que empiece por él.
    final compatibles = <Player>[];
    for (final jugador in jugadores) {
      final palabrasNombre = palabrasPorJugador[jugador.id]!;
      if (palabrasNombre.isEmpty) continue;
      final nombreSet = palabrasNombre.toSet();
      if (!palabrasCompletas.every(nombreSet.contains)) continue;
      if (prefijoTruncado != null && !palabrasNombre.any((w) => w.startsWith(prefijoTruncado))) continue;
      compatibles.add(jugador);
    }
    if (compatibles.isEmpty) continue;

    for (final jugador in compatibles) {
      final palabrasNombre = palabrasPorJugador[jugador.id]!;
      final nombreCompletoNormalizado = palabrasNombre.join(' ');
      final cubiertas = palabrasCompletas.length + (prefijoTruncado != null ? 1 : 0);
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

bool _terminaTruncada(String texto) {
  final t = texto.trim();
  return t.endsWith('...') || t.endsWith('…');
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
