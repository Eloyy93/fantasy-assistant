import 'package:flutter/widgets.dart';

/// Sin anuncios dentro de la app web: AdSense no permite servir anuncios en
/// pantallas sin contenido editorial (buscadores, listas, formularios,
/// estados vacíos), y toda la app es de ese tipo. Los anuncios de la web
/// viven solo en las guías estáticas (/guias/).
Widget buildAdsenseSidebar() => const SizedBox.shrink();
