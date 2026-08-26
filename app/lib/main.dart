import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'history_charts.dart';
import 'pitch_view.dart';
import 'theme.dart';

/// Token FCM de este dispositivo, disponible tras arrancar la app. Nulo
/// hasta que _setupPushNotifications() termine (o si Firebase falla).
String? currentFcmToken;

Future<void> _setupPushNotifications() async {
  await Firebase.initializeApp();
  final messaging = FirebaseMessaging.instance;

  await messaging.requestPermission();

  final token = await messaging.getToken();
  currentFcmToken = token;

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
    currentFcmToken = newToken;
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
      theme: fantasyTheme,
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

  String _source = 'biwenger';
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

  void _onSourceChanged(String source) {
    setState(() => _source = source);
    _search(_controller.text);
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final players = await _api.searchPlayers(query, source: _source);
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
      appBar: AppBar(
        title: const Text('Fantasy Assistant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Optimizador de alineación',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LineupScreen(api: _api, source: _source)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'biwenger', label: Text('Biwenger')),
                ButtonSegment(value: 'laligafantasy', label: Text('LaLiga Fantasy')),
              ],
              selected: {_source},
              onSelectionChanged: (selection) => _onSourceChanged(selection.first),
            ),
          ),
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
          if (!_loading && _error == null && _players.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Sin jugadores disponibles en esta fuente ahora mismo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _players.length,
              itemBuilder: (context, index) {
                final player = _players[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colorForPosicion(player.posicion),
                    child: Text(
                      player.posicion,
                      style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(player.nombre),
                  subtitle: Text(player.equipo),
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
  bool? _suscrito; // null mientras se comprueba el estado inicial
  bool _cambiandoSuscripcion = false;
  PlayerHistorial? _historial;
  String? _errorHistorial;

  @override
  void initState() {
    super.initState();
    _load();
    _cargarEstadoSuscripcion();
    _cargarHistorial();
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

  Future<void> _cargarHistorial() async {
    try {
      final historial = await widget.api.getHistorial(widget.player.id);
      if (!mounted) return;
      setState(() => _historial = historial);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorHistorial = 'No se pudo cargar el historial: $e');
    }
  }

  Future<void> _cargarEstadoSuscripcion() async {
    final token = currentFcmToken;
    if (token == null) {
      setState(() => _suscrito = false);
      return;
    }
    try {
      final suscripciones = await widget.api.getSubscriptions(token);
      if (!mounted) return;
      setState(() => _suscrito = suscripciones.contains(widget.player.id));
    } catch (_) {
      if (!mounted) return;
      setState(() => _suscrito = false);
    }
  }

  Future<void> _toggleSuscripcion() async {
    final token = currentFcmToken;
    if (token == null || _suscrito == null) return;

    setState(() => _cambiandoSuscripcion = true);
    try {
      if (_suscrito!) {
        await widget.api.unsubscribe(fcmToken: token, playerId: widget.player.id);
      } else {
        await widget.api.subscribe(fcmToken: token, playerId: widget.player.id);
      }
      if (!mounted) return;
      setState(() => _suscrito = !_suscrito!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo actualizar la alerta: $e')));
    } finally {
      if (mounted) setState(() => _cambiandoSuscripcion = false);
    }
  }

  Widget _buildBotonAlertas(BuildContext context) {
    if (_suscrito == null) {
      return const SizedBox(height: 40, width: 40, child: CircularProgressIndicator(strokeWidth: 2));
    }

    final activada = _suscrito!;
    final icono = _cambiandoSuscripcion
        ? const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Icon(activada ? Icons.notifications_active : Icons.notifications_off_outlined);
    final etiqueta = Text(activada ? 'Alertas de precio activadas' : 'Activar alertas de precio');
    final onPressed = (_cambiandoSuscripcion || currentFcmToken == null) ? null : _toggleSuscripcion;

    return SizedBox(
      width: double.infinity,
      child: activada
          ? FilledButton.icon(onPressed: onPressed, icon: icono, label: etiqueta)
          : OutlinedButton.icon(onPressed: onPressed, icon: icono, label: etiqueta),
    );
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: colorForPosicion(widget.player.posicion),
                  child: Text(
                    widget.player.posicion,
                    style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Text(widget.player.equipo, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text('Precio: ${(widget.player.precio / 1000000).toStringAsFixed(2)} M€'),
            const SizedBox(height: 20),
            _buildBotonAlertas(context),
            const SizedBox(height: 24),
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
            const SizedBox(height: 32),
            Text('Evolución de precio', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_errorHistorial != null)
              Text(_errorHistorial!, style: TextStyle(color: Theme.of(context).colorScheme.error))
            else if (_historial == null)
              const Center(child: CircularProgressIndicator())
            else
              PriceHistoryChart(precios: _historial!.precios),
            const SizedBox(height: 32),
            Text('Puntos por jornada', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_errorHistorial == null && _historial != null) PointsHistoryChart(puntos: _historial!.puntos),
          ],
        ),
      ),
    );
  }
}

const _formaciones = ['4-3-3', '4-4-2', '3-4-3', '3-5-2', '5-3-2', '5-4-1'];

class LineupScreen extends StatefulWidget {
  final FantasyApiClient api;
  final String source;

  const LineupScreen({super.key, required this.api, required this.source});

  @override
  State<LineupScreen> createState() => _LineupScreenState();
}

class _LineupScreenState extends State<LineupScreen> {
  final _presupuestoController = TextEditingController(text: '60000000');
  String _formacion = '4-3-3';
  OptimizedLineup? _resultado;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _presupuestoController.dispose();
    super.dispose();
  }

  Future<void> _calcular() async {
    final presupuesto = int.tryParse(_presupuestoController.text.trim());
    if (presupuesto == null || presupuesto <= 0) {
      setState(() => _error = 'Introduce un presupuesto válido en euros');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _resultado = null;
    });
    try {
      final resultado = await widget.api.getLineup(
        presupuesto: presupuesto,
        formacion: _formacion,
        source: widget.source,
      );
      if (!mounted) return;
      setState(() => _resultado = resultado);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Optimizador (${widget.source == 'biwenger' ? 'Biwenger' : 'LaLiga Fantasy'})'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _presupuestoController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Presupuesto (€)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _formacion,
            decoration: const InputDecoration(labelText: 'Formación', border: OutlineInputBorder()),
            items: _formaciones.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
            onChanged: (value) => setState(() => _formacion = value ?? _formacion),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _calcular,
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Calcular alineación óptima'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_resultado != null) ...[
            const SizedBox(height: 24),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_resultado!.formacion} — ${_resultado!.puntosEsperados.toStringAsFixed(1)} pts esperados',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Presupuesto usado: ${(_resultado!.presupuestoUsado / 1000000).toStringAsFixed(2)} M€'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            PitchView(jugadores: _resultado!.jugadores),
            const SizedBox(height: 24),
            Text('Detalle', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            ..._resultado!.jugadores.map(
              (j) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorForPosicion(j.posicion),
                  child: Text(
                    j.posicion,
                    style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(j.nombre),
                subtitle: Text('${j.equipo} · ${j.puntosEsperados.toStringAsFixed(1)} pts esperados'),
                trailing: Text('${(j.precio / 1000000).toStringAsFixed(2)} M€'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
