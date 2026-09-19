import 'package:flutter/material.dart';
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

Future<void> abrirGuias() async {
  await launchUrl(Uri.parse('https://masterfantasy.es/guias/'), mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
}

Future<void> abrirPrivacidad() => _abrir('privacidad.html');
Future<void> abrirCookies() => _abrir('cookies.html');
Future<void> abrirAvisoLegal() => _abrir('aviso-legal.html');

const String kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.eloy.fantasyassistant.fantasy_assistant_app';

Future<void> abrirPlayStore() async {
  final uri = Uri.parse(kPlayStoreUrl);
  await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
}

/// El badge oficial "Disponible en Google Play" servido por el propio
/// Google — se usa la imagen alojada por ellos en vez de guardar una
/// copia local, que es lo que piden sus normas de marca para este badge.
class PlayStoreBadge extends StatelessWidget {
  final double height;

  const PlayStoreBadge({super.key, this.height = 42});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: abrirPlayStore,
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        'https://play.google.com/intl/es/badges/static/images/badges/es_badge_web_generic.png',
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }
}
