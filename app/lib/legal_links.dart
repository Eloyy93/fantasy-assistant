import 'package:url_launcher/url_launcher.dart';

/// Páginas legales estáticas servidas junto a la web (app/web/legal/) —
/// se abren en una pestaña/navegador aparte tanto desde la app Android
/// como desde la propia web, por eso usan la URL absoluta del despliegue
/// en vez de una ruta relativa.
const String _kLegalBaseUrl = 'https://master-fantasy.pages.dev/legal';

Future<void> _abrir(String pagina) async {
  final uri = Uri.parse('$_kLegalBaseUrl/$pagina');
  await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
}

Future<void> abrirPrivacidad() => _abrir('privacidad.html');
Future<void> abrirCookies() => _abrir('cookies.html');
Future<void> abrirAvisoLegal() => _abrir('aviso-legal.html');
