import 'package:flutter_test/flutter_test.dart';
import 'package:fantasy_assistant_app/lineup_scan_io.dart';
import 'package:fantasy_assistant_app/api_client.dart';

Player _jugador(String id, String nombre) =>
    Player(id: id, source: 'biwenger', nombre: nombre, equipo: 'Equipo', posicion: 'DEL', precio: 1000000);

void main() {
  final mercado = [
    _jugador('1', 'Rodrygo'),
    _jugador('2', 'Alexander Sørloth'),
    _jugador('3', 'Pedri'),
    _jugador('4', 'Diego Costa'),
    _jugador('5', 'Altimira'),
    _jugador('6', 'Romero'),
    _jugador('7', 'Romero Segundo'),
  ];

  test('tolera una letra confundida por el OCR (Rodrigo -> Rodrygo)', () {
    final candidatos = emparejarJugadores(['Rodrigo'], mercado);
    expect(candidatos.any((c) => c.jugador.id == '1'), isTrue);
  });

  test('tolera un caracter numerico confundido con una letra (S0rloth -> Sorloth)', () {
    final candidatos = emparejarJugadores(['S0rloth'], mercado);
    expect(candidatos.any((c) => c.jugador.id == '2'), isTrue);
  });

  test('sigue exigiendo coincidencia exacta en palabras cortas (Pedro no es Pedri)', () {
    final candidatos = emparejarJugadores(['Pedro'], mercado);
    expect(candidatos.any((c) => c.jugador.id == '3'), isFalse);
  });

  test('nombre truncado con punto suspensivo sigue funcionando (Diego Co...)', () {
    final candidatos = emparejarJugadores(['Diego Co...'], mercado);
    expect(candidatos.any((c) => c.jugador.id == '4'), isTrue);
  });

  test('abreviatura sin puntos con letra de OCR confundida (A. Altimirs)', () {
    final candidatos = emparejarJugadores(['A. Altimirs'], mercado);
    expect(candidatos.any((c) => c.jugador.id == '5'), isTrue);
  });

  test('un precio pegado al nombre no rompe la coincidencia (Diego Costa 18,5M)', () {
    final candidatos = emparejarJugadores(['Diego Costa 18,5M'], mercado);
    expect(candidatos.any((c) => c.jugador.id == '4'), isTrue);
  });

  test('un código de equipo pegado al nombre no rompe la coincidencia (Alexander Sørloth RMA)', () {
    final candidatos = emparejarJugadores(['Alexander Sørloth RMA'], mercado);
    expect(candidatos.any((c) => c.jugador.id == '2'), isTrue);
  });

  test('apellido ambiguo entre varios jugadores baja la confianza pero no los descarta', () {
    final candidatos = emparejarJugadores(['Romero'], mercado);
    final ids = candidatos.map((c) => c.jugador.id).toSet();
    expect(ids.containsAll({'6', '7'}), isTrue);
    for (final c in candidatos) {
      expect(c.confianza, lessThanOrEqualTo(0.65));
    }
  });
}
