import 'dart:convert';
import 'package:http/http.dart' as http;

/// URL base del backend Fantasy Assistant, ya desplegado en Railway.
const String kApiBaseUrl = 'https://fantasy-assistant-production-d8fd.up.railway.app';

class Player {
  final String id;
  final String source;
  final String nombre;
  final String equipo;
  final String posicion;
  final int precio;
  final String fotoUrl;

  Player({
    required this.id,
    required this.source,
    required this.nombre,
    required this.equipo,
    required this.posicion,
    required this.precio,
    this.fotoUrl = '',
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      source: json['source'] as String,
      nombre: json['nombre'] as String,
      equipo: json['equipo'] as String,
      posicion: json['posicion'] as String,
      precio: json['precio'] as int,
      fotoUrl: json['foto_url'] as String? ?? '',
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

class LineupPlayer {
  final String playerId;
  final String nombre;
  final String equipo;
  final String posicion;
  final int precio;
  final double puntosEsperados;
  final String fotoUrl;

  LineupPlayer({
    required this.playerId,
    required this.nombre,
    required this.equipo,
    required this.posicion,
    required this.precio,
    required this.puntosEsperados,
    this.fotoUrl = '',
  });

  factory LineupPlayer.fromJson(Map<String, dynamic> json) {
    return LineupPlayer(
      playerId: json['player_id'] as String,
      nombre: json['nombre'] as String,
      equipo: json['equipo'] as String,
      posicion: json['posicion'] as String,
      precio: json['precio'] as int,
      puntosEsperados: (json['puntos_esperados'] as num).toDouble(),
      fotoUrl: json['foto_url'] as String? ?? '',
    );
  }
}

class OptimizedLineup {
  final String formacion;
  final List<LineupPlayer> jugadores;
  final double puntosEsperados;
  final int presupuestoUsado;

  OptimizedLineup({
    required this.formacion,
    required this.jugadores,
    required this.puntosEsperados,
    required this.presupuestoUsado,
  });

  factory OptimizedLineup.fromJson(Map<String, dynamic> json) {
    return OptimizedLineup(
      formacion: json['formacion'] as String,
      jugadores: (json['jugadores'] as List<dynamic>)
          .map((e) => LineupPlayer.fromJson(e as Map<String, dynamic>))
          .toList(),
      puntosEsperados: (json['puntos_esperados'] as num).toDouble(),
      presupuestoUsado: json['presupuesto_usado'] as int,
    );
  }
}

class PricePoint {
  final DateTime fecha;
  final int precio;

  PricePoint({required this.fecha, required this.precio});

  factory PricePoint.fromJson(Map<String, dynamic> json) {
    return PricePoint(
      fecha: DateTime.parse(json['fecha'] as String),
      precio: json['precio'] as int,
    );
  }
}

class PointsEntry {
  final int jornada;
  final int puntos;

  PointsEntry({required this.jornada, required this.puntos});

  factory PointsEntry.fromJson(Map<String, dynamic> json) {
    return PointsEntry(jornada: json['jornada'] as int, puntos: json['puntos'] as int);
  }
}

class PlayerHistorial {
  final List<PricePoint> precios;
  final List<PointsEntry> puntos;

  PlayerHistorial({required this.precios, required this.puntos});

  factory PlayerHistorial.fromJson(Map<String, dynamic> json) {
    return PlayerHistorial(
      precios: (json['precios'] as List<dynamic>)
          .map((e) => PricePoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      puntos: (json['puntos'] as List<dynamic>)
          .map((e) => PointsEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TeamPlayer {
  final String id;
  final String source;
  final String nombre;
  final String equipo;
  final String posicion;
  final int precio;
  final int? variacionPrecio;
  final int? puntosUltimaJornada;
  final int puntosTemporada;
  final String? slot;
  final String fotoUrl;

  TeamPlayer({
    required this.id,
    required this.source,
    required this.nombre,
    required this.equipo,
    required this.posicion,
    required this.precio,
    required this.variacionPrecio,
    required this.puntosUltimaJornada,
    required this.puntosTemporada,
    this.slot,
    this.fotoUrl = '',
  });

  factory TeamPlayer.fromJson(Map<String, dynamic> json) {
    return TeamPlayer(
      id: json['id'] as String,
      source: json['source'] as String,
      nombre: json['nombre'] as String,
      equipo: json['equipo'] as String,
      posicion: json['posicion'] as String,
      precio: json['precio'] as int,
      variacionPrecio: json['variacion_precio'] as int?,
      puntosUltimaJornada: json['puntos_ultima_jornada'] as int?,
      puntosTemporada: json['puntos_temporada'] as int,
      slot: json['slot'] as String?,
      fotoUrl: json['foto_url'] as String? ?? '',
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

  Future<List<Player>> searchPlayers(String query, {required String source}) async {
    final uri = Uri.parse('$baseUrl/players').replace(
      queryParameters: {if (query.isNotEmpty) 'q': query, 'limit': '30', 'source': source},
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

  Future<OptimizedLineup> getLineup({
    required int presupuesto,
    String formacion = '4-3-3',
    required String source,
  }) async {
    final uri = Uri.parse('$baseUrl/lineup').replace(
      queryParameters: {'presupuesto': '$presupuesto', 'formacion': formacion, 'source': source},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      throw ApiException(body['detail']?.toString() ?? 'Error ${response.statusCode} al calcular la alineación');
    }
    return OptimizedLineup.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  Future<PlayerHistorial> getHistorial(String playerId) async {
    final uri = Uri.parse('$baseUrl/players/$playerId/historial');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw ApiException('Error ${response.statusCode} al obtener el historial');
    }
    return PlayerHistorial.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  Future<void> registerDevice(String fcmToken) async {
    final uri = Uri.parse('$baseUrl/devices');
    await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fcm_token': fcmToken}),
        )
        .timeout(const Duration(seconds: 10));
  }

  Future<void> subscribe({required String fcmToken, required String playerId}) async {
    final uri = Uri.parse('$baseUrl/subscriptions');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fcm_token': fcmToken, 'player_id': playerId}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode >= 300) {
      throw ApiException('Error ${response.statusCode} al suscribirse');
    }
  }

  Future<void> unsubscribe({required String fcmToken, required String playerId}) async {
    final uri = Uri.parse('$baseUrl/subscriptions');
    final response = await http
        .delete(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fcm_token': fcmToken, 'player_id': playerId}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode >= 300) {
      throw ApiException('Error ${response.statusCode} al desuscribirse');
    }
  }

  Future<List<String>> getSubscriptions(String fcmToken) async {
    final uri = Uri.parse('$baseUrl/subscriptions').replace(queryParameters: {'fcm_token': fcmToken});
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw ApiException('Error ${response.statusCode} al leer suscripciones');
    }
    final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
    return data.cast<String>();
  }

  Future<List<TeamPlayer>> getTeam(String deviceId, {String? source}) async {
    final uri = Uri.parse('$baseUrl/team').replace(
      queryParameters: {'device_id': deviceId, if (source != null) 'source': source},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw ApiException('Error ${response.statusCode} al leer la plantilla');
    }
    final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
    return data.map((e) => TeamPlayer.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> addToTeam({required String deviceId, required String playerId, String? slot}) async {
    final uri = Uri.parse('$baseUrl/team');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'device_id': deviceId, 'player_id': playerId, if (slot != null) 'slot': slot}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode >= 300) {
      String detalle = 'Error ${response.statusCode}';
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (body['detail'] != null) detalle = body['detail'].toString();
      } catch (_) {}
      throw ApiException(detalle);
    }
  }

  Future<bool> isInTeam({required String deviceId, required String playerId}) async {
    final uri = Uri.parse('$baseUrl/team/contains').replace(
      queryParameters: {'device_id': deviceId, 'player_id': playerId},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw ApiException('Error ${response.statusCode} al comprobar la plantilla');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return body['en_plantilla'] as bool;
  }

  Future<void> removeFromTeam({required String deviceId, required String playerId}) async {
    final uri = Uri.parse('$baseUrl/team');
    final response = await http
        .delete(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'device_id': deviceId, 'player_id': playerId}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode >= 300) {
      throw ApiException('Error ${response.statusCode} al quitar de la plantilla');
    }
  }

  Future<void> clearTeam({required String deviceId, required String source}) async {
    final uri = Uri.parse('$baseUrl/team/clear').replace(
      queryParameters: {'device_id': deviceId, 'source': source},
    );
    final response = await http.delete(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode >= 300) {
      throw ApiException('Error ${response.statusCode} al vaciar la plantilla');
    }
  }

  Future<String> getFormacion({required String deviceId, required String source}) async {
    final uri = Uri.parse('$baseUrl/team/formacion').replace(
      queryParameters: {'device_id': deviceId, 'source': source},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw ApiException('Error ${response.statusCode} al leer la formación');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return body['formacion'] as String;
  }

  Future<void> setFormacion({required String deviceId, required String source, required String formacion}) async {
    final uri = Uri.parse('$baseUrl/team/formacion');
    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'device_id': deviceId, 'source': source, 'formacion': formacion}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode >= 300) {
      throw ApiException('Error ${response.statusCode} al cambiar la formación');
    }
  }

  Future<List<TeamPlayer>> getRecomendados({
    required String source,
    required String posicion,
    List<String> excluir = const [],
  }) async {
    final uri = Uri.parse('$baseUrl/team/recomendados').replace(
      queryParameters: {'source': source, 'posicion': posicion, 'excluir': excluir.join(',')},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw ApiException('Error ${response.statusCode} al buscar recomendaciones');
    }
    final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
    return data.map((e) => TeamPlayer.fromJson(e as Map<String, dynamic>)).toList();
  }
}
