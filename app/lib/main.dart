import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'ads_service.dart';
import 'api_client.dart';
import 'device_id.dart';
import 'history_charts.dart';
import 'pitch_view.dart';
import 'purchase_service.dart';
import 'theme.dart';

/// Token FCM de este dispositivo, disponible tras arrancar la app. Nulo
/// hasta que _setupPushNotifications() termine (o si Firebase falla).
String? currentFcmToken;

Future<void> _setupPushNotifications() async {
  // Firebase no está configurado para web (requeriría FlutterFire CLI +
  // credenciales propias del proyecto web) — la versión web funciona sin
  // notificaciones push, el resto de la app no depende de ellas.
  if (kIsWeb) return;
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
  unawaited(initAds());
  unawaited(PurchaseService.instance.init());
  runApp(const FantasyAssistantApp());
}

class FantasyAssistantApp extends StatelessWidget {
  const FantasyAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Master Fantasy',
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

  String _source = 'laligafantasy';
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
        title: const Text('Master Fantasy'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Menú',
            onSelected: (opcion) {
              switch (opcion) {
                case 'plantilla':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamScreen(api: _api)));
                case 'optimizador':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => LineupScreen(api: _api, source: _source)),
                  );
                case 'comparar':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CompareScreen(api: _api, source: _source)),
                  );
                case 'chollos':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => BargainsScreen(api: _api, source: _source)),
                  );
                case 'sin_anuncios':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NoAdsScreen()));
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'plantilla',
                child: ListTile(
                  leading: Icon(Icons.shield_rounded),
                  title: Text('Mi plantilla'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'optimizador',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_rounded),
                  title: Text('Optimizador de alineación'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'comparar',
                child: ListTile(
                  leading: Icon(Icons.compare_arrows_rounded),
                  title: Text('Comparar jugadores'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'chollos',
                child: ListTile(
                  leading: Icon(Icons.local_fire_department_rounded),
                  title: Text('Chollos'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              // Sin anuncios ni compras en la versión web (google_mobile_ads
              // e in_app_purchase son solo Android/iOS) — el menú no ofrece
              // algo que no puede hacer nada.
              if (!kIsWeb)
                const PopupMenuItem(
                  value: 'sin_anuncios',
                  child: ListTile(
                    leading: Icon(Icons.block_rounded),
                    title: Text('Quitar anuncios'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
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
                      Icon(
                        _source == 'laligafantasy' ? Icons.cloud_off_rounded : Icons.search_off_rounded,
                        size: 40,
                        color: kTextTertiary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _source == 'laligafantasy'
                            ? 'La API oficial de LaLiga Fantasy está caída ahora mismo.'
                            : 'Sin jugadores disponibles en esta fuente ahora mismo.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kTextSecondary),
                      ),
                      if (_source == 'laligafantasy') ...[
                        const SizedBox(height: 6),
                        const Text(
                          'No es un fallo de la app: se sincroniza sola en\ncuanto LaLiga recupere el servicio.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: kTextTertiary, fontSize: 12),
                        ),
                      ],
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
          // El banner va aquí, como un hijo más del Column — puesto en
          // Scaffold.bottomNavigationBar (donde parece "natural" un banner
          // fijo abajo) dejaba el resto de la pantalla en blanco: verificado
          // en emulador que esa combinación concreta (platform view de
          // AdMob + slot bottomNavigationBar) rompe el compositing del resto
          // del árbol de widgets. Aquí, como hijo normal del body, funciona.
          ValueListenableBuilder<bool>(
            valueListenable: PurchaseService.instance.adsRemoved,
            builder: (context, sinAnuncios, _) => sinAnuncios
                ? const SizedBox.shrink()
                : const SafeArea(top: false, child: Center(child: BannerAdBar())),
          ),
        ],
      ),
    );
  }
}

class CompareScreen extends StatefulWidget {
  final FantasyApiClient api;
  final String source;

  const CompareScreen({super.key, required this.api, required this.source});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  late String _source = widget.source;
  Player? _jugadorA;
  Player? _jugadorB;
  (ComparePlayer, ComparePlayer)? _resultado;
  bool _loading = false;
  String? _error;

  void _onSourceChanged(String source) {
    setState(() {
      _source = source;
      _jugadorA = null;
      _jugadorB = null;
      _resultado = null;
    });
  }

  Future<void> _elegir(bool esA) async {
    final excluir = <String>{};
    if (esA && _jugadorB != null) excluir.add(_jugadorB!.id);
    if (!esA && _jugadorA != null) excluir.add(_jugadorA!.id);

    final elegido = await showModalBottomSheet<Player>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PlayerPickerSheet(api: widget.api, source: _source, excluir: excluir),
    );
    if (elegido == null) return;

    setState(() {
      if (esA) {
        _jugadorA = elegido;
      } else {
        _jugadorB = elegido;
      }
      _resultado = null;
      _error = null;
    });
    _comparar();
  }

  Future<void> _comparar() async {
    final a = _jugadorA;
    final b = _jugadorB;
    if (a == null || b == null) return;

    setState(() => _loading = true);
    try {
      final resultado = await widget.api.comparePlayers(a: a.id, b: b.id);
      if (!mounted) return;
      setState(() => _resultado = resultado);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo comparar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comparar jugadores')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _SourceToggle(source: _source, onChanged: _onSourceChanged),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _CompareSlot(player: _jugadorA, onTap: () => _elegir(true))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('VS', style: TextStyle(fontWeight: FontWeight.w800, color: kTextTertiary)),
              ),
              Expanded(child: _CompareSlot(player: _jugadorB, onTap: () => _elegir(false))),
            ],
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_resultado != null) _CompareTable(a: _resultado!.$1, b: _resultado!.$2),
        ],
      ),
    );
  }
}

class _CompareSlot extends StatelessWidget {
  final Player? player;
  final VoidCallback onTap;

  const _CompareSlot({required this.player, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = player;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          color: kSurfaceColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kBorderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (p == null)
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: kSurfaceHighColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: kBorderColor),
                ),
                child: const Icon(Icons.add_rounded, color: kTextSecondary),
              )
            else
              PlayerAvatar(fotoUrl: p.fotoUrl, posicion: p.posicion, size: 52),
            const SizedBox(height: 8),
            Text(
              p?.nombre ?? 'Elegir jugador',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: p == null ? kTextSecondary : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareTable extends StatelessWidget {
  final ComparePlayer a;
  final ComparePlayer b;

  const _CompareTable({required this.a, required this.b});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _fila('Precio', '${(a.precio / 1000000).toStringAsFixed(2)} M€', '${(b.precio / 1000000).toStringAsFixed(2)} M€'),
        _fila('Variación reciente', _variacionTexto(a.variacionPrecio), _variacionTexto(b.variacionPrecio)),
        _fila(
          'Puntos temporada',
          '${a.puntosTemporada}',
          '${b.puntosTemporada}',
          mejorA: a.puntosTemporada > b.puntosTemporada ? true : (b.puntosTemporada > a.puntosTemporada ? false : null),
        ),
        _fila(
          'Últimas jornadas',
          a.puntosRecientes.isEmpty ? '—' : a.puntosRecientes.map((p) => '${p.puntos}').join(' · '),
          b.puntosRecientes.isEmpty ? '—' : b.puntosRecientes.map((p) => '${p.puntos}').join(' · '),
        ),
        _fila('Próximo rival', a.proximoRival ?? '—', b.proximoRival ?? '—'),
        if ((a.analisisRival?.dificultad != null) || (b.analisisRival?.dificultad != null))
          _fila('Dificultad rival', _dificultadTexto(a.analisisRival), _dificultadTexto(b.analisisRival)),
        if ((a.analisisRival?.mediaPrevios != null) || (b.analisisRival?.mediaPrevios != null))
          _fila('Histórico vs. ese rival', _historicoRivalTexto(a.analisisRival), _historicoRivalTexto(b.analisisRival)),
      ],
    );
  }

  String _variacionTexto(int? variacion) {
    if (variacion == null) return '—';
    final signo = variacion > 0 ? '+' : '';
    return '$signo${(variacion / 1000).toStringAsFixed(0)} k€';
  }

  String _dificultadTexto(RivalAnalysis? analisis) {
    final dificultad = analisis?.dificultad;
    if (dificultad == null) return '—';
    final etiqueta = dificultad >= 65 ? 'duro' : (dificultad <= 35 ? 'flojo' : 'medio');
    return '$dificultad/100 ($etiqueta)';
  }

  String _historicoRivalTexto(RivalAnalysis? analisis) {
    final media = analisis?.mediaPrevios;
    if (media == null) return '—';
    return '${media.toStringAsFixed(1)} pts/partido (${analisis!.partidosPrevios})';
  }

  Widget _fila(String label, String valorA, String valorB, {bool? mejorA}) {
    final colorA = mejorA == true ? kMintAccent : Colors.white;
    final colorB = mejorA == false ? kMintAccent : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          SectionLabel(label),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  valorA,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colorA),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  valorB,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colorB),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NoAdsScreen extends StatefulWidget {
  const NoAdsScreen({super.key});

  @override
  State<NoAdsScreen> createState() => _NoAdsScreenState();
}

class _NoAdsScreenState extends State<NoAdsScreen> {
  bool _procesando = false;

  Future<void> _suscribirse() async {
    setState(() => _procesando = true);
    try {
      await PurchaseService.instance.comprar();
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _restaurar() async {
    setState(() => _procesando = true);
    try {
      await PurchaseService.instance.restaurar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Compras restauradas.')));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = PurchaseService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Quitar anuncios')),
      body: ValueListenableBuilder<bool>(
        valueListenable: service.adsRemoved,
        builder: (context, sinAnuncios, _) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(sinAnuncios ? Icons.check_circle_rounded : Icons.block_rounded, size: 48, color: kMintAccent),
                const SizedBox(height: 16),
                Text(
                  sinAnuncios ? 'Ya tienes los anuncios desactivados' : 'Navega sin anuncios',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  sinAnuncios
                      ? 'Gracias por apoyar la app. Puedes gestionar o cancelar la suscripción desde Google Play.'
                      : 'Suscripción mensual para quitar la franja de anuncios de toda la app.',
                  style: const TextStyle(color: kTextSecondary, fontSize: 14),
                ),
                const SizedBox(height: 28),
                if (!sinAnuncios) ...[
                  if (service.productos.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(service.productos.first.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${service.productos.first.price} / mes',
                                    style: const TextStyle(color: kMintAccent, fontWeight: FontWeight.w800, fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (service.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(service.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: (_procesando || service.productos.isEmpty) ? null : _suscribirse,
                    child: _procesando
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Suscribirse'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _procesando ? null : _restaurar,
                    child: const Text('Restaurar compra anterior'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class TeamScreen extends StatefulWidget {
  final FantasyApiClient api;

  const TeamScreen({super.key, required this.api});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  String? _deviceId;
  String _source = 'laligafantasy';
  String _formacion = '4-3-3';
  List<TeamPlayer>? _jugadores;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final id = await getDeviceId();
    if (!mounted) return;
    setState(() => _deviceId = id);
    await _cargar();
  }

  Future<void> _cargar() async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    setState(() => _error = null);
    try {
      final resultados = await Future.wait([
        widget.api.getTeam(deviceId, source: _source),
        widget.api.getFormacion(deviceId: deviceId, source: _source),
      ]);
      if (!mounted) return;
      setState(() {
        _jugadores = resultados[0] as List<TeamPlayer>;
        _formacion = resultados[1] as String;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar la plantilla: $e');
    }
  }

  void _onSourceChanged(String source) {
    setState(() {
      _source = source;
      _jugadores = null;
    });
    _cargar();
  }

  Future<void> _cambiarFormacion(String formacion) async {
    final deviceId = _deviceId;
    if (deviceId == null || formacion == _formacion) return;
    setState(() => _formacion = formacion);
    try {
      await widget.api.setFormacion(deviceId: deviceId, source: _source, formacion: formacion);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo cambiar la formación: $e')));
    }
  }

  Future<void> _quitarDelEquipo(TeamPlayer jugador) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    setState(() => _jugadores = _jugadores!.where((j) => j.id != jugador.id).toList());
    try {
      await widget.api.removeFromTeam(deviceId: deviceId, playerId: jugador.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo quitar: $e')));
      _cargar();
    }
  }

  Future<void> _quitarDelCampo(TeamPlayer jugador) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      await widget.api.addToTeam(deviceId: deviceId, playerId: jugador.id);
      _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo actualizar: $e')));
    }
  }

  Future<void> _elegirParaHueco(String slot, {TeamPlayer? actual}) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    final posicion = posicionDeSlot(slot);
    final ocupandoElCampo = (_jugadores ?? [])
        .where((j) => j.slot != null && slotsDeFormacion(_formacion).contains(j.slot))
        .map((j) => j.id)
        .toSet();

    final elegido = await showModalBottomSheet<Player>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PlayerPickerSheet(api: widget.api, source: _source, posicion: posicion, excluir: ocupandoElCampo),
    );
    if (elegido == null) return;
    try {
      await widget.api.addToTeam(deviceId: deviceId, playerId: elegido.id, slot: slot);
      _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo añadir: $e')));
    }
  }

  Future<void> _anadirAlBanquillo() async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    final elegido = await showModalBottomSheet<Player>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PlayerPickerSheet(api: widget.api, source: _source, excluir: (_jugadores ?? []).map((j) => j.id).toSet()),
    );
    if (elegido == null) return;
    try {
      await widget.api.addToTeam(deviceId: deviceId, playerId: elegido.id);
      _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo añadir: $e')));
    }
  }

  void _verFicha(TeamPlayer j) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrediccionScreen(
          player: Player(id: j.id, source: j.source, nombre: j.nombre, equipo: j.equipo, posicion: j.posicion, precio: j.precio),
          api: widget.api,
        ),
      ),
    );
  }

  void _onTapSlot(String slot, TeamPlayer? ocupante) {
    if (ocupante == null) {
      _elegirParaHueco(slot);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: PlayerAvatar(fotoUrl: ocupante.fotoUrl, posicion: ocupante.posicion),
              title: Text(ocupante.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(ocupante.equipo),
            ),
            ListTile(
              leading: const Icon(Icons.badge_rounded),
              title: const Text('Ver ficha'),
              onTap: () {
                Navigator.pop(sheetContext);
                _verFicha(ocupante);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Cambiar jugador'),
              onTap: () {
                Navigator.pop(sheetContext);
                _elegirParaHueco(slot, actual: ocupante);
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline_rounded),
              title: const Text('Quitar del campo'),
              subtitle: const Text('Pasa al banquillo, sigue en tu plantilla'),
              onTap: () {
                Navigator.pop(sheetContext);
                _quitarDelCampo(ocupante);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Theme.of(sheetContext).colorScheme.error),
              title: Text('Eliminar de la plantilla', style: TextStyle(color: Theme.of(sheetContext).colorScheme.error)),
              onTap: () {
                Navigator.pop(sheetContext);
                _quitarDelEquipo(ocupante);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _vaciarPlantilla() async {
    final deviceId = _deviceId;
    if (deviceId == null || (_jugadores ?? []).isEmpty) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Vaciar la plantilla?'),
        content: Text(
          'Se quitarán los ${_jugadores!.length} jugadores de tu plantilla de '
          '${_source == 'biwenger' ? 'Biwenger' : 'LaLiga Fantasy'}. Esto no se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Vaciar', style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await widget.api.clearTeam(deviceId: deviceId, source: _source);
      _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo vaciar la plantilla: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hayJugadores = (_jugadores ?? []).isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi plantilla'),
        actions: [
          IconButton(
            icon: const Icon(Icons.military_tech_rounded),
            tooltip: 'Capitán óptimo',
            onPressed: (hayJugadores && _deviceId != null)
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CaptainScreen(api: widget.api, deviceId: _deviceId!, source: _source),
                      ),
                    )
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Vaciar plantilla',
            onPressed: hayJugadores ? _vaciarPlantilla : null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final slots = slotsDeFormacion(_formacion);
    final asignados = <String, TeamPlayer>{
      for (final j in _jugadores ?? [])
        if (j.slot != null && slots.contains(j.slot)) j.slot!: j,
    };
    final banquillo = (_jugadores ?? []).where((j) => j.slot == null || !slots.contains(j.slot)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        _SourceToggle(source: _source, onChanged: _onSourceChanged),
        const SizedBox(height: 12),
        _FormationSelector(formacion: _formacion, onChanged: _cambiarFormacion),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (_jugadores == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          FormationPitchView(
            formacion: _formacion,
            asignados: asignados,
            onTapSlot: (slot) => _onTapSlot(slot, asignados[slot]),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const SectionLabel('Banquillo'),
              const Spacer(),
              TextButton.icon(
                onPressed: _anadirAlBanquillo,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Añadir'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (banquillo.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Toca un hueco vacío del campo para colocar jugadores, o añade aquí a los que tengas de reserva.',
                style: TextStyle(color: kTextSecondary),
              ),
            )
          else
            for (final jugador in banquillo) ...[
              _TeamPlayerCard(jugador: jugador, onQuitar: () => _quitarDelEquipo(jugador)),
              const SizedBox(height: 10),
            ],
        ],
      ],
    );
  }
}

class _FormationSelector extends StatelessWidget {
  final String formacion;
  final ValueChanged<String> onChanged;

  const _FormationSelector({required this.formacion, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kFormaciones.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final opcion = kFormaciones.keys.elementAt(index);
          final selected = opcion == formacion;
          return ChoiceChip(
            label: Text(opcion),
            selected: selected,
            onSelected: (_) => onChanged(opcion),
            selectedColor: kMintAccent.withValues(alpha: 0.2),
            side: BorderSide(color: selected ? kMintAccent.withValues(alpha: 0.6) : kBorderColor),
            labelStyle: TextStyle(color: selected ? kMintAccent : kTextSecondary, fontWeight: FontWeight.w700),
            backgroundColor: kSurfaceColor,
          );
        },
      ),
    );
  }
}

class _TeamPlayerCard extends StatelessWidget {
  final TeamPlayer jugador;
  final VoidCallback onQuitar;

  const _TeamPlayerCard({required this.jugador, required this.onQuitar});

  @override
  Widget build(BuildContext context) {
    final variacion = jugador.variacionPrecio;
    final subiendo = variacion != null && variacion > 0;
    final bajando = variacion != null && variacion < 0;
    final colorVariacion = subiendo ? kMintAccent : (bajando ? const Color(0xFFE85C4A) : kTextTertiary);
    final iconoVariacion = subiendo
        ? Icons.arrow_upward_rounded
        : (bajando ? Icons.arrow_downward_rounded : Icons.remove_rounded);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderColor),
      ),
      child: Row(
        children: [
          PlayerAvatar(fotoUrl: jugador.fotoUrl, posicion: jugador.posicion),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(jugador.nombre, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(jugador.equipo, style: const TextStyle(fontSize: 13, color: kTextSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(jugador.precio / 1000000).toStringAsFixed(2)} M€',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconoVariacion, size: 13, color: colorVariacion),
                  if (variacion != null)
                    Text(
                      '${(variacion.abs() / 1000).toStringAsFixed(0)} k€',
                      style: TextStyle(fontSize: 11, color: colorVariacion, fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(width: 8),
                  Icon(Icons.sports_soccer_rounded, size: 12, color: kTextTertiary),
                  const SizedBox(width: 2),
                  Text(
                    jugador.puntosUltimaJornada != null
                        ? '${jugador.puntosUltimaJornada} · ${jugador.puntosTemporada} pts'
                        : '${jugador.puntosTemporada} pts',
                    style: const TextStyle(fontSize: 11, color: kTextTertiary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: kTextTertiary),
            tooltip: 'Quitar de la plantilla',
            onPressed: onQuitar,
          ),
        ],
      ),
    );
  }
}

/// Buscador de jugadores en un bottom sheet, para añadir a la plantilla.
/// Selector de jugador en un bottom sheet: si se da [posicion], muestra
/// primero los mejores por puntos de temporada para ese hueco (estilo
/// Futbin) y debajo un buscador libre, filtrado a esa misma posición.
class _PlayerPickerSheet extends StatefulWidget {
  final FantasyApiClient api;
  final String source;
  final String? posicion;
  final Set<String> excluir;

  const _PlayerPickerSheet({required this.api, required this.source, this.posicion, required this.excluir});

  @override
  State<_PlayerPickerSheet> createState() => _PlayerPickerSheetState();
}

class _PlayerPickerSheetState extends State<_PlayerPickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<TeamPlayer> _recomendados = [];
  List<Player> _resultados = [];
  bool _loadingRecomendados = false;
  bool _loadingBusqueda = false;
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    if (widget.posicion != null) _cargarRecomendados();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _cargarRecomendados() async {
    setState(() => _loadingRecomendados = true);
    try {
      final recomendados = await widget.api.getRecomendados(
        source: widget.source,
        posicion: widget.posicion!,
        excluir: widget.excluir.toList(),
      );
      if (!mounted) return;
      setState(() => _recomendados = recomendados);
    } catch (_) {
      // silencioso: si falla, el usuario siempre puede usar el buscador
    } finally {
      if (mounted) setState(() => _loadingRecomendados = false);
    }
  }

  Future<void> _buscar(String query) async {
    setState(() => _loadingBusqueda = true);
    try {
      final resultados = await widget.api.searchPlayers(query, source: widget.source);
      if (!mounted) return;
      setState(
        () => _resultados = resultados
            .where((p) => !widget.excluir.contains(p.id))
            .where((p) => widget.posicion == null || p.posicion == widget.posicion)
            .toList(),
      );
    } catch (_) {
      // silencioso: el buscador simplemente no muestra resultados
    } finally {
      if (mounted) setState(() => _loadingBusqueda = false);
    }
  }

  void _onChanged(String query) {
    setState(() => _buscando = query.isNotEmpty);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _buscar(query));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: kBorderColor, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                controller: _controller,
                autofocus: false,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: widget.posicion != null ? 'Buscar otro ${widget.posicion}' : 'Buscar jugador para añadir',
                  prefixIcon: const Icon(Icons.search_rounded, color: kTextSecondary),
                ),
              ),
            ),
            SizedBox(
              height: 3,
              child: (_loadingRecomendados || _loadingBusqueda)
                  ? const LinearProgressIndicator(minHeight: 3, backgroundColor: Colors.transparent)
                  : null,
            ),
            Expanded(
              child: _buscando
                  ? ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: _resultados.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final player = _resultados[index];
                        return _PlayerCard(player: player, onTap: () => Navigator.of(context).pop(player));
                      },
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        if (widget.posicion != null) ...[
                          const SectionLabel('Recomendados'),
                          const SizedBox(height: 10),
                          if (_recomendados.isEmpty && !_loadingRecomendados)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Sin recomendaciones disponibles todavía.', style: TextStyle(color: kTextSecondary)),
                            ),
                          for (final jugador in _recomendados) ...[
                            _RecomendadoCard(
                              jugador: jugador,
                              onTap: () => Navigator.of(context).pop(
                                Player(
                                  id: jugador.id,
                                  source: jugador.source,
                                  nombre: jugador.nombre,
                                  equipo: jugador.equipo,
                                  posicion: jugador.posicion,
                                  precio: jugador.precio,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecomendadoCard extends StatelessWidget {
  final TeamPlayer jugador;
  final VoidCallback onTap;

  const _RecomendadoCard({required this.jugador, required this.onTap});

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
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorderColor)),
          child: Row(
            children: [
              PlayerAvatar(fotoUrl: jugador.fotoUrl, posicion: jugador.posicion),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(jugador.nombre, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(jugador.equipo, style: const TextStyle(fontSize: 13, color: kTextSecondary)),
                  ],
                ),
              ),
              Row(
                children: [
                  Icon(Icons.sports_soccer_rounded, size: 14, color: kMintAccent),
                  const SizedBox(width: 3),
                  Text(
                    '${jugador.puntosTemporada} pts',
                    style: const TextStyle(fontSize: 13, color: kMintAccent, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CaptainScreen extends StatefulWidget {
  final FantasyApiClient api;
  final String deviceId;
  final String source;

  const CaptainScreen({super.key, required this.api, required this.deviceId, required this.source});

  @override
  State<CaptainScreen> createState() => _CaptainScreenState();
}

class _CaptainScreenState extends State<CaptainScreen> {
  List<CaptainCandidate>? _candidatos;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final candidatos = await widget.api.getCapitan(deviceId: widget.deviceId, source: widget.source);
      if (!mounted) return;
      setState(() => _candidatos = candidatos);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo calcular el capitán óptimo: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidatos = _candidatos ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Capitán óptimo')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const Text(
              'Quién de tu once titular tiene más probabilidad de puntuar alto esta jornada, para el multiplicador de capitán.',
              style: TextStyle(color: kTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (!_loading && _error == null && candidatos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('Coloca jugadores en el campo para ver la recomendación', style: TextStyle(color: kTextSecondary)),
                ),
              ),
            for (var i = 0; i < candidatos.length; i++) ...[
              _CaptainCard(candidato: candidatos[i], top: i == 0),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _CaptainCard extends StatelessWidget {
  final CaptainCandidate candidato;
  final bool top;

  const _CaptainCard({required this.candidato, required this.top});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: top ? kMintAccent.withValues(alpha: 0.6) : kBorderColor),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              PlayerAvatar(fotoUrl: candidato.fotoUrl, posicion: candidato.posicion),
              if (top)
                const Positioned(
                  top: -6,
                  left: -6,
                  child: Icon(Icons.workspace_premium_rounded, color: kMintAccent, size: 18),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidato.nombre, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  candidato.proximoRival != null ? '${candidato.equipo} · vs ${candidato.proximoRival}' : candidato.equipo,
                  style: const TextStyle(fontSize: 13, color: kTextSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${candidato.puntosEsperados.toStringAsFixed(1)} pts',
                style: TextStyle(
                  fontSize: 13,
                  color: top ? kMintAccent : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (candidato.dificultadRival != null) ...[
                const SizedBox(height: 2),
                Text(
                  'rival ${candidato.dificultadRival}/100',
                  style: const TextStyle(fontSize: 12, color: kTextTertiary, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class BargainsScreen extends StatefulWidget {
  final FantasyApiClient api;
  final String source;

  const BargainsScreen({super.key, required this.api, required this.source});

  @override
  State<BargainsScreen> createState() => _BargainsScreenState();
}

class _BargainsScreenState extends State<BargainsScreen> {
  late String _source = widget.source;
  List<Bargain> _chollos = [];
  bool _loading = true;
  String? _error;
  bool _notificar = false;
  bool _loadingPref = currentFcmToken != null;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarPreferencia();
  }

  void _onSourceChanged(String source) {
    setState(() => _source = source);
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final chollos = await widget.api.getBargains(source: _source);
      if (!mounted) return;
      setState(() => _chollos = chollos);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudieron cargar los chollos: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cargarPreferencia() async {
    final token = currentFcmToken;
    if (token == null) return;
    try {
      final activado = await widget.api.getChollosPref(token);
      if (!mounted) return;
      setState(() => _notificar = activado);
    } catch (_) {
      // Sin red al abrir la pantalla: se deja el interruptor en su valor
      // por defecto, el usuario puede reintentar tocándolo.
    } finally {
      if (mounted) setState(() => _loadingPref = false);
    }
  }

  Future<void> _cambiarPreferencia(bool activar) async {
    final token = currentFcmToken;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todavía no se ha podido registrar este dispositivo para notificaciones')),
      );
      return;
    }
    setState(() => _notificar = activar);
    try {
      await widget.api.setChollosPref(fcmToken: token, activar: activar);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notificar = !activar);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chollos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'Jugadores cuya relación puntos/precio destaca frente a los demás de su posición.',
            style: const TextStyle(color: kTextSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _SourceToggle(source: _source, onChanged: _onSourceChanged),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: kSurfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorderColor),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notificar,
              onChanged: _loadingPref ? null : _cambiarPreferencia,
              activeThumbColor: kMintAccent,
              title: const Text('Avisarme de chollos nuevos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Notificación cuando aparezca un jugador infravalorado', style: TextStyle(fontSize: 12, color: kTextSecondary)),
            ),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (!_loading && _error == null && _chollos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No hay chollos claros ahora mismo', style: TextStyle(color: kTextSecondary))),
            ),
          for (final chollo in _chollos) ...[
            _BargainCard(chollo: chollo),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _BargainCard extends StatelessWidget {
  final Bargain chollo;

  const _BargainCard({required this.chollo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderColor),
      ),
      child: Row(
        children: [
          PlayerAvatar(fotoUrl: chollo.fotoUrl, posicion: chollo.posicion),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chollo.nombre, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${chollo.equipo} · ${(chollo.precio / 1000000).toStringAsFixed(2)} M€',
                  style: const TextStyle(fontSize: 13, color: kTextSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${chollo.puntosEsperados.toStringAsFixed(1)} pts',
                style: const TextStyle(fontSize: 13, color: kMintAccent, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'z ${chollo.zscore.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 12, color: kTextTertiary, fontWeight: FontWeight.w600),
              ),
            ],
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
          _segment(context, 'laligafantasy', 'LaLiga Fantasy', 'assets/logos/laligafantasy.png'),
          _segment(context, 'biwenger', 'Biwenger', 'assets/logos/biwenger.svg'),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String value, String label, String logoAsset) {
    final selected = source == value;
    final logo = logoAsset.endsWith('.svg')
        ? SvgPicture.asset(logoAsset, height: 26)
        : Image.asset(logoAsset, height: 26);

    return Expanded(
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? kMintAccent.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              border: selected ? Border.all(color: kMintAccent.withValues(alpha: 0.6)) : null,
            ),
            child: Center(child: logo),
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
              PlayerAvatar(fotoUrl: player.fotoUrl, posicion: player.posicion),
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

/// Explica el "por qué" del ajuste de confianza: próximo rival, y si hay
/// datos, qué tan duro es y cómo le fue a este jugador contra él antes.
class _RivalContexto extends StatelessWidget {
  final RivalAnalysis rival;

  const _RivalContexto({required this.rival});

  @override
  Widget build(BuildContext context) {
    final partes = <String>['Próximo rival: ${rival.rival} (${rival.casa ? 'Casa' : 'Fuera'})'];
    if (rival.dificultad != null) {
      final etiqueta = rival.dificultad! >= 65 ? 'duro' : (rival.dificultad! <= 35 ? 'flojo' : 'medio');
      partes.add('dificultad ${rival.dificultad}/100 ($etiqueta)');
    }
    if (rival.mediaPrevios != null) {
      partes.add('media histórica contra él: ${rival.mediaPrevios!.toStringAsFixed(1)} pts (${rival.partidosPrevios} partido${rival.partidosPrevios == 1 ? '' : 's'})');
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.event_rounded, size: 16, color: kTextTertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(partes.join(' · '), style: const TextStyle(color: kTextSecondary, fontSize: 12.5)),
        ),
      ],
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

  String? _deviceId;
  bool? _enPlantilla; // null mientras se comprueba el estado inicial
  bool _cambiandoPlantilla = false;

  @override
  void initState() {
    super.initState();
    _load();
    _cargarEstadoSuscripcion();
    _cargarHistorial();
    _cargarEstadoPlantilla();
  }

  Future<void> _cargarEstadoPlantilla() async {
    try {
      final id = await getDeviceId();
      if (!mounted) return;
      _deviceId = id;
      final enPlantilla = await widget.api.isInTeam(deviceId: id, playerId: widget.player.id);
      if (!mounted) return;
      setState(() => _enPlantilla = enPlantilla);
    } catch (_) {
      if (!mounted) return;
      setState(() => _enPlantilla = false);
    }
  }

  Future<void> _togglePlantilla() async {
    final deviceId = _deviceId;
    if (deviceId == null || _enPlantilla == null) return;

    setState(() => _cambiandoPlantilla = true);
    try {
      if (_enPlantilla!) {
        await widget.api.removeFromTeam(deviceId: deviceId, playerId: widget.player.id);
      } else {
        await widget.api.addToTeam(deviceId: deviceId, playerId: widget.player.id);
      }
      if (!mounted) return;
      setState(() => _enPlantilla = !_enPlantilla!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo actualizar la plantilla: $e')));
    } finally {
      if (mounted) setState(() => _cambiandoPlantilla = false);
    }
  }

  Widget _buildBotonPlantilla(BuildContext context) {
    if (_enPlantilla == null) {
      return const SizedBox(
        height: 52,
        child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final enPlantilla = _enPlantilla!;
    final icono = _cambiandoPlantilla
        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(enPlantilla ? Icons.shield_rounded : Icons.add_rounded);
    final etiqueta = Text(enPlantilla ? 'En tu plantilla' : 'Añadir a mi plantilla');
    final onPressed = (_cambiandoPlantilla || _deviceId == null) ? null : _togglePlantilla;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(onPressed: onPressed, icon: icono, label: etiqueta),
    );
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
                    PlayerAvatar(fotoUrl: widget.player.fotoUrl, posicion: widget.player.posicion, size: 80),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              PositionBadge(posicion: widget.player.posicion, size: 24),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.player.equipo,
                                  style: const TextStyle(fontSize: 14, color: kTextSecondary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
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
            _buildBotonPlantilla(context),
            const SizedBox(height: 10),
            _buildBotonAlertas(context),
            const SizedBox(height: 28),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_prediccion == null && _error == null) const Center(child: CircularProgressIndicator()),
            if (_prediccion != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                      if (_prediccion!.rival != null) ...[
                        const Divider(height: 24),
                        _RivalContexto(rival: _prediccion!.rival!),
                      ],
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
                    : PointsHistoryChart(puntos: _historial!.puntos, source: widget.player.source),
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
  bool _aplicando = false;
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

  Future<void> _aplicarAMiPlantilla() async {
    final resultado = _resultado;
    if (resultado == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Aplicar esta alineación?'),
        content: Text(
          'Sustituirá tu plantilla actual de ${widget.source == 'biwenger' ? 'Biwenger' : 'LaLiga Fantasy'} '
          'por estos ${resultado.jugadores.length} jugadores en formación ${resultado.formacion}. Esto no se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Aplicar', style: TextStyle(color: kMintAccent)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _aplicando = true);
    try {
      final deviceId = await getDeviceId();
      await widget.api.clearTeam(deviceId: deviceId, source: widget.source);
      await widget.api.setFormacion(deviceId: deviceId, source: widget.source, formacion: resultado.formacion);

      final contadorPorPosicion = <String, int>{};
      for (final jugador in resultado.jugadores) {
        final indice = (contadorPorPosicion[jugador.posicion] ?? 0) + 1;
        contadorPorPosicion[jugador.posicion] = indice;
        final slot = jugador.posicion == 'POR' ? 'POR1' : '${jugador.posicion}$indice';
        await widget.api.addToTeam(deviceId: deviceId, playerId: jugador.playerId, slot: slot);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alineación aplicada a tu plantilla')));
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamScreen(api: widget.api)));
    } catch (e) {
      print('[lineup->team] error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo aplicar la alineación: $e')));
    } finally {
      if (mounted) setState(() => _aplicando = false);
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
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _aplicando ? null : _aplicarAMiPlantilla,
              icon: _aplicando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kMintAccent),
                    )
                  : const Icon(Icons.shield_rounded, color: kMintAccent),
              label: Text(_aplicando ? 'Aplicando…' : 'Añadir a mi plantilla'),
            ),
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
                        PlayerAvatar(fotoUrl: j.fotoUrl, posicion: j.posicion),
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
