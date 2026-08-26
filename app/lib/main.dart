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
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: 'Optimizador de alineación',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LineupScreen(api: _api, source: _source)),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: _SourceToggle(source: _source, onChanged: _onSourceChanged),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Buscar jugador',
                prefixIcon: Icon(Icons.search_rounded, color: kTextSecondary),
              ),
            ),
          ),
          SizedBox(
            height: 3,
            child: _loading
                ? const LinearProgressIndicator(minHeight: 3, backgroundColor: Colors.transparent)
                : null,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (!_loading && _error == null && _players.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off_rounded, size: 40, color: kTextTertiary),
                      const SizedBox(height: 12),
                      Text(
                        'Sin jugadores disponibles en esta fuente ahora mismo.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kTextSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                itemCount: _players.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final player = _players[index];
                  return _PlayerCard(
                    player: player,
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

class _SourceToggle extends StatelessWidget {
  final String source;
  final ValueChanged<String> onChanged;

  const _SourceToggle({required this.source, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderColor),
      ),
      child: Row(
        children: [
          _segment(context, 'biwenger', 'Biwenger'),
          _segment(context, 'laligafantasy', 'LaLiga Fantasy'),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String value, String label) {
    final selected = source == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? kMintAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.black : kTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final Player player;
  final VoidCallback onTap;

  const _PlayerCard({required this.player, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurfaceColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorderColor),
          ),
          child: Row(
            children: [
              PositionBadge(posicion: player.posicion),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(player.nombre, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(player.equipo, style: const TextStyle(fontSize: 13, color: kTextSecondary)),
                  ],
                ),
              ),
              Text(
                '${(player.precio / 1000000).toStringAsFixed(2)} M€',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: kTextTertiary, size: 20),
            ],
          ),
        ),
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
      return const SizedBox(
        height: 52,
        child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final activada = _suscrito!;
    final icono = _cambiandoSuscripcion
        ? const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Icon(activada ? Icons.notifications_active_rounded : Icons.notifications_none_rounded);
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
        return Icons.trending_up_rounded;
      case 'baja':
        return Icons.trending_down_rounded;
      default:
        return Icons.trending_flat_rounded;
    }
  }

  Color _colorFor(String prediccion) {
    switch (prediccion) {
      case 'sube':
        return kMintAccent;
      case 'baja':
        return const Color(0xFFE85D6B);
      default:
        return kTextSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.player.nombre)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    PositionBadge(posicion: widget.player.posicion, size: 44),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.player.equipo, style: const TextStyle(fontSize: 14, color: kTextSecondary)),
                          const SizedBox(height: 2),
                          Text(
                            '${(widget.player.precio / 1000000).toStringAsFixed(2)} M€',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildBotonAlertas(context),
            const SizedBox(height: 28),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_prediccion == null && _error == null) const Center(child: CircularProgressIndicator()),
            if (_prediccion != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _colorFor(_prediccion!.prediccion).withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_iconFor(_prediccion!.prediccion), size: 28, color: _colorFor(_prediccion!.prediccion)),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _prediccion!.prediccion.toUpperCase(),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Confianza: ${(_prediccion!.confianza * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(color: kTextSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 28),
            const SectionLabel('Evolución de precio'),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: _errorHistorial != null
                    ? Text(_errorHistorial!, style: TextStyle(color: Theme.of(context).colorScheme.error))
                    : _historial == null
                        ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                        : PriceHistoryChart(precios: _historial!.precios),
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Puntos por jornada'),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: _errorHistorial != null || _historial == null
                    ? const SizedBox(height: 40)
                    : PointsHistoryChart(puntos: _historial!.puntos),
              ),
            ),
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
        title: Text('Optimizador · ${widget.source == 'biwenger' ? 'Biwenger' : 'LaLiga Fantasy'}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _presupuestoController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Presupuesto (€)'),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _formacion,
                    decoration: const InputDecoration(labelText: 'Formación'),
                    dropdownColor: kSurfaceHighColor,
                    items: _formaciones.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                    onChanged: (value) => setState(() => _formacion = value ?? _formacion),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _calcular,
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Calcular alineación óptima'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_resultado != null) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatTile(label: 'Formación', value: _resultado!.formacion),
                    StatTile(
                      label: 'Pts. esperados',
                      value: _resultado!.puntosEsperados.toStringAsFixed(1),
                      valueColor: kMintAccent,
                    ),
                    StatTile(
                      label: 'Presupuesto',
                      value: '${(_resultado!.presupuestoUsado / 1000000).toStringAsFixed(1)}M€',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            PitchView(jugadores: _resultado!.jugadores),
            const SizedBox(height: 24),
            const SectionLabel('Detalle'),
            const SizedBox(height: 10),
            ..._resultado!.jugadores.map(
              (j) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: kSurfaceColor,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kBorderColor),
                    ),
                    child: Row(
                      children: [
                        PositionBadge(posicion: j.posicion),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(j.nombre, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                '${j.equipo} · ${j.puntosEsperados.toStringAsFixed(1)} pts',
                                style: const TextStyle(fontSize: 13, color: kTextSecondary),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${(j.precio / 1000000).toStringAsFixed(2)} M€',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
