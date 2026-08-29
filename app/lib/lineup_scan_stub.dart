import 'api_client.dart';

/// Versión sin implementación para plataformas sin dart:io (web) — la
/// importación de plantilla por captura es solo Android (usa ML Kit,
/// sin soporte web), así que nunca debería llamarse aquí; existe solo
/// para que main.dart compile en web sin depender de dart:io.
class CandidatoEscaneado {
  final Player jugador;
  final double confianza;

  CandidatoEscaneado({required this.jugador, required this.confianza});
}

Future<List<String>> reconocerTexto(String rutaImagen) async {
  throw UnsupportedError('El reconocimiento de texto no está disponible en la versión web.');
}

List<CandidatoEscaneado> emparejarJugadores(List<String> lineasTexto, List<Player> jugadores) => [];
