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

  // ML Kit no siempre da una línea de texto por jugador: cuando varias
  // tarjetas quedan a la misma altura en la rejilla (ej. los tres del
  // centro del campo, o dos delanteros seguidos), a veces las funde en
  // una sola línea de texto — ej. "Rubén G.. Unai Lop... Josan" son en
  // realidad TRES jugadores, no un nombre con espacios raros. La única
  // pista fiable para separarlos es el propio punto suspensivo que la
  // interfaz ya usa para marcar cada nombre cortado, así que cualquier
  // línea se trocea primero por esos puntos antes de intentar casarla —
  // cada trozo se procesa después exactamente igual que si hubiera sido
  // su propia línea desde el principio (incluido el caso normal de una
  // sola línea sin ningún punto, que no se trocea).
  final lineasIndividuales = lineasTexto.expand(_dividirPorTruncamiento).toList();

  for (final lineaOriginal in lineasIndividuales) {
    final normalizada = _normalizar(_quitarPuntosSuspensivos(lineaOriginal));
    if (normalizada.length < 3) continue;

    // ML Kit a menudo funde en una sola "línea" el nombre con texto que
    // está pegado o muy cerca visualmente (precio, puntos, dorsal, código
    // de equipo) — esos tokens son mayoritariamente dígitos, así que se
    // descartan aquí. Sin este filtro, un precio como "18,5M" se colaba
    // como palabra a exigir en el nombre del jugador y rompía la
    // coincidencia de la línea entera, aunque el nombre en sí estuviera
    // bien leído. Ojo: NO se descarta cualquier token con un dígito suelto
    // (ej. "s0rloth", donde el OCR confundió una "o" con un "0" dentro del
    // propio nombre) — solo cuando los dígitos son mayoría del token.
    final todasLasPalabras = normalizada.split(' ').where((p) => p.isNotEmpty && !_esRuidoNumerico(p)).toList();
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
    String? inicial;
    if (todasLasPalabras.length == 1) {
      palabrasCompletas = todasLasPalabras.where((p) => p.length >= 4).toSet();
      prefijo = null;
    } else {
      final palabras = List<String>.from(todasLasPalabras);
      prefijo = palabras.removeLast();
      palabrasCompletas = palabras.where((p) => p.length >= 4).toSet();
      // Una letra suelta antes del apellido (ej. "C. Romero") es casi
      // siempre la inicial del nombre de pila abreviado — se descartaba
      // como ruido, y con apellidos comunes (Romero, García...) eso deja
      // pasar a TODOS los jugadores con ese apellido sin ningún filtro
      // extra. Se usa como pista: el nombre del jugador tiene que tener
      // alguna palabra que empiece por esa letra.
      final iniciales = palabras.where((p) => p.length == 1).toList();
      if (iniciales.length == 1) inicial = iniciales.first;
    }

    final compatibles = _buscarCompatibles(palabrasCompletas, prefijo, inicial, jugadores, palabrasPorJugador);
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
/// nombre (o parecerse lo bastante — ver [_palabraCompatible], para
/// tolerar errores típicos de OCR como confundir letras parecidas), si
/// hay [prefijo] el nombre tiene que tener alguna palabra que empiece por
/// él (con el mismo margen de tolerancia), y si hay [inicial] (letra
/// suelta del nombre de pila abreviado) el nombre tiene que tener alguna
/// palabra que empiece por esa letra.
List<Player> _buscarCompatibles(
  Set<String> palabrasCompletas,
  String? prefijo,
  String? inicial,
  List<Player> jugadores,
  Map<String, List<String>> palabrasPorJugador,
) {
  if (palabrasCompletas.isEmpty && (prefijo == null || prefijo.length < 3)) return const [];
  // Se tolera como máximo UNA palabra de la línea (completa o el prefijo
  // final) que no encaje con nada del nombre — pero SOLO si la línea trae
  // al menos otras DOS palabras que sí encajan. Con solo dos palabras en
  // total (ej. "Pedro Bigas"), tolerar que una de las dos no encaje
  // equivale a exigir solo la mitad del nombre — eso colaba jugadores que
  // no tenían nada que ver, solo porque una palabra suelta coincidía por
  // casualidad. Con tres o más (ej. "Alexander Sørloth RMA", donde "RMA"
  // es ruido pegado al nombre real de dos palabras) sigue teniendo sentido
  // tolerar una.
  final totalTokens = palabrasCompletas.length + (prefijo != null ? 1 : 0);
  final tolerablesRuido = totalTokens >= 3 ? 1 : 0;
  final compatibles = <Player>[];
  for (final jugador in jugadores) {
    final palabrasNombre = palabrasPorJugador[jugador.id]!;
    if (palabrasNombre.isEmpty) continue;
    var noEncajan = palabrasCompletas.where((p) => !palabrasNombre.any((w) => _palabraCompatible(w, p))).length;
    final prefijoEncaja = prefijo == null || palabrasNombre.any((w) => _prefijoCompatible(w, prefijo));
    if (!prefijoEncaja) noEncajan++;
    if (noEncajan > tolerablesRuido || noEncajan == totalTokens) continue;
    if (inicial != null && !palabrasNombre.any((w) => w.startsWith(inicial))) continue;
    compatibles.add(jugador);
  }
  return compatibles;
}

/// Cuántos errores de OCR (letra sustituida/perdida/añadida) se toleran
/// según la longitud del texto — 0 para palabras muy cortas (ahí
/// cualquier tolerancia coincidiría con casi cualquier cosa), 1 para las
/// típicas de nombre/apellido, 2 para las largas (más margen para que el
/// OCR se equivoque en más de una letra sin perder la coincidencia).
int _tolerancia(int longitud) {
  // <=5: 0 — en palabras cortas, tolerar 1 error confundiría nombres
  // reales distintos entre sí (ej. "Pedro" vs "Pedri", distancia 1).
  if (longitud <= 5) return 0;
  if (longitud <= 8) return 1;
  return 2;
}

/// true si [palabraNombre] (del mercado) y [palabraTexto] (leída por OCR)
/// son la misma palabra o se parecen lo bastante como para asumir que el
/// OCR se equivocó en alguna letra — ej. "Rodrygo" vs "Rodrigo" (leído
/// con la "y" confundida), o "S0rloth" vs "Sorloth" (un "0" en vez de
/// "o"). Antes se exigía coincidencia exacta de la palabra completa, lo
/// que hacía perder jugadores que sí estaban en la captura solo porque el
/// OCR leyó una letra mal.
bool _palabraCompatible(String palabraNombre, String palabraTexto) {
  if (palabraNombre == palabraTexto) return true;
  // Distingue longitudes muy distintas antes de calcular la distancia —
  // evita, por ejemplo, que "gol" cuele como parecido a "goles" con la
  // tolerancia de una palabra larga.
  if ((palabraNombre.length - palabraTexto.length).abs() > _tolerancia(palabraTexto.length)) return false;
  return _distanciaEdicion(palabraNombre, palabraTexto) <= _tolerancia(palabraTexto.length);
}

/// Igual que [_palabraCompatible] pero para el prefijo truncado (nombre
/// cortado por la interfaz, ej. "Diego Co..." por "Diego Costa") — compara
/// el prefijo contra el trozo inicial de la misma longitud de la palabra
/// del mercado, con el mismo margen de tolerancia a errores de OCR.
bool _prefijoCompatible(String palabraNombre, String prefijo) {
  if (palabraNombre.startsWith(prefijo)) return true;
  if (prefijo.length > palabraNombre.length) return false;
  final inicioNombre = palabraNombre.substring(0, prefijo.length);
  // Se probó a dar más margen de tolerancia aquí que en una palabra
  // completa, pensando que un prefijo corto necesitaba más ayuda frente a
  // errores de OCR — al revés: un prefijo corto es AMBIGUO de por sí (más
  // apellidos comparten sus primeras letras que la palabra entera), así
  // que dar más margen todavía multiplicaba los falsos positivos (ej.
  // "Alti" pasaba a confundirse con "Alto..." de otro jugador distinto).
  // Se usa la misma tolerancia estricta que para una palabra completa.
  return _distanciaEdicion(inicioNombre, prefijo) <= _tolerancia(prefijo.length);
}

/// Distancia de Levenshtein clásica (mínimo de sustituciones/inserciones/
/// borrados para convertir [a] en [b]) — programación dinámica con dos
/// filas, sin necesitar la matriz completa ya que las palabras son cortas.
int _distanciaEdicion(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var filaAnterior = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final filaActual = List<int>.filled(b.length + 1, 0);
    filaActual[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final costoSustitucion = a[i - 1] == b[j - 1] ? 0 : 1;
      filaActual[j] = [
        filaActual[j - 1] + 1, // inserción
        filaAnterior[j] + 1, // borrado
        filaAnterior[j - 1] + costoSustitucion, // sustitución
      ].reduce((x, y) => x < y ? x : y);
    }
    filaAnterior = filaActual;
  }
  return filaAnterior[b.length];
}

bool _esRuidoNumerico(String p) {
  final digitos = p.replaceAll(RegExp(r'[^0-9]'), '').length;
  return digitos >= p.length - digitos;
}

List<String> _dividirPorTruncamiento(String linea) {
  return linea.split(RegExp(r'\.{2,}|…')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

String _quitarPuntosSuspensivos(String texto) {
  var t = texto.trim();
  if (t.endsWith('...')) return t.substring(0, t.length - 3);
  if (t.endsWith('…')) return t.substring(0, t.length - 1);
  return t;
}

String _normalizar(String texto) {
  // Además de los acentos españoles, algunos jugadores extranjeros de
  // LaLiga tienen letras nórdicas/centroeuropeas en el nombre (ej.
  // "Alexander Sørloth", "Isak") — sin mapearlas aquí, el reemplazo
  // genérico de _normalizar las convertía en un espacio (caracter no
  // alfanumérico), partiendo la palabra en dos y rompiendo la
  // coincidencia con un jugador que sí estaba en la captura.
  const conAcento = 'áéíóúüñÁÉÍÓÚÜÑøØåÅäÄöÖçÇ';
  const sinAcento = 'aeiouunAEIOUUNoOaAaAoOcC';
  var resultado = texto.toLowerCase();
  for (var i = 0; i < conAcento.length; i++) {
    resultado = resultado.replaceAll(conAcento[i], sinAcento[i].toLowerCase());
  }
  return resultado.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}
