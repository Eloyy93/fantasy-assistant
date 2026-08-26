import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';

Future<void> _setupPushNotifications() async {
  await Firebase.initializeApp();
  final messaging = FirebaseMessaging.instance;

  await messaging.requestPermission();

  final token = await messaging.getToken();

  print('[push] FCM token: $token');
  if (token != null) {
    try {
      await FantasyApiClient().registerDevice(token);
      print('[push] Dispositivo registrado en el backend');
    } catch (e) {
      print('[push] Fallo registrando dispositivo: $e');
      // Sin conexión al arrancar: no bloquea la app, simplemente no
      // recibirá push hasta el próximo arranque con red.
    }
  }

  // Si el token rota (reinstalación, cambio de dispositivo, etc.), Firebase
  // emite uno nuevo: hay que re-registrarlo.
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    FantasyApiClient().registerDevice(newToken).catchError((_) {});
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_setupPushNotifications());
  runApp(const FantasyAssistantApp());
}

class FantasyAssistantApp extends StatelessWidget {
  const FantasyAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fantasy Assistant',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const PlayerSearchScreen(),
    );
  }
}

class PlayerSearchScreen extends StatefulWidget {
  const PlayerSearchScreen({super.key});

  @override
  State<PlayerSearchScreen> createState() => _PlayerSearchScreenState();
}

class _PlayerSearchScreenState extends State<PlayerSearchScreen> {
  final _api = FantasyApiClient();
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Player> _players = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final players = await _api.searchPlayers(query);
      if (!mounted) return;
      setState(() => _players = players);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo conectar con el backend: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fantasy Assistant')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              decoration: const InputDecoration(
                labelText: 'Buscar jugador',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _players.length,
              itemBuilder: (context, index) {
                final player = _players[index];
                return ListTile(
                  title: Text(player.nombre),
                  subtitle: Text('${player.equipo} · ${player.posicion}'),
                  trailing: Text('${(player.precio / 1000000).toStringAsFixed(2)} M€'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => PrediccionScreen(player: player, api: _api)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PrediccionScreen extends StatefulWidget {
  final Player player;
  final FantasyApiClient api;

  const PrediccionScreen({super.key, required this.player, required this.api});

  @override
  State<PrediccionScreen> createState() => _PrediccionScreenState();
}

class _PrediccionScreenState extends State<PrediccionScreen> {
  Prediccion? _prediccion;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.api.getPrediccion(widget.player.id);
      if (!mounted) return;
      setState(() => _prediccion = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo obtener la predicción: $e');
    }
  }

  IconData _iconFor(String prediccion) {
    switch (prediccion) {
      case 'sube':
        return Icons.trending_up;
      case 'baja':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  Color _colorFor(String prediccion, BuildContext context) {
    switch (prediccion) {
      case 'sube':
        return Colors.green;
      case 'baja':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.player.nombre)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.player.equipo} · ${widget.player.posicion}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Precio: ${(widget.player.precio / 1000000).toStringAsFixed(2)} M€'),
            const SizedBox(height: 32),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_prediccion == null && _error == null) const Center(child: CircularProgressIndicator()),
            if (_prediccion != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(_iconFor(_prediccion!.prediccion), size: 40, color: _colorFor(_prediccion!.prediccion, context)),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_prediccion!.prediccion.toUpperCase(),
                              style: Theme.of(context).textTheme.headlineSmall),
                          Text('Confianza: ${(_prediccion!.confianza * 100).toStringAsFixed(0)}%'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
