import 'dart:convert';
import 'package:http/http.dart' as http;

/// URL base del backend Fantasy Assistant.
///
/// - Emulador Android: 10.0.2.2 apunta al "localhost" de tu PC.
/// - Móvil físico en la misma red: cambia esto por la IP LAN de tu PC
///   (ej. "http://192.168.1.50:8000"), o mejor aún, por la URL del backend
///   ya desplegado en Railway/Fly.io cuando lo tengas.
const String kApiBaseUrl = 'http://10.0.2.2:8000';

class Player {
  final String id;
  final String source;
  final String nombre;
  final String equipo;
  final String posicion;
  final int precio;

  Player({
    required this.id,
    required this.source,
    required this.nombre,
    required this.equipo,
    required this.posicion,
    required this.precio,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      source: json['source'] as String,
      nombre: json['nombre'] as String,
      equipo: json['equipo'] as String,
      posicion: json['posicion'] as String,
      precio: json['precio'] as int,
    );
  }
}

class Prediccion {
  final String playerId;
  final String prediccion;
  final double confianza;

  Prediccion({
    required this.playerId,
    required this.prediccion,
    required this.confianza,
  });

  factory Prediccion.fromJson(Map<String, dynamic> json) {
    return Prediccion(
      playerId: json['player_id'] as String,
      prediccion: json['prediccion'] as String,
      confianza: (json['confianza'] as num).toDouble(),
    );
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class FantasyApiClient {
  final String baseUrl;

  FantasyApiClient({this.baseUrl = kApiBaseUrl});

  Future<List<Player>> searchPlayers(String query) async {
    final uri = Uri.parse('$baseUrl/players').replace(
      queryParameters: {if (query.isNotEmpty) 'q': query, 'limit': '30'},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw ApiException('Error ${response.statusCode} al buscar jugadores');
    }
    final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
    return data.map((e) => Player.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Prediccion> getPrediccion(String playerId) async {
    final uri = Uri.parse('$baseUrl/players/$playerId/prediccion');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw ApiException('Error ${response.statusCode} al obtener la predicción');
    }
    return Prediccion.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }
}
