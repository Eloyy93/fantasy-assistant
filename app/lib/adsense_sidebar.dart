import 'package:flutter/widgets.dart';

import 'adsense_sidebar_stub.dart' if (dart.library.html) 'adsense_sidebar_web.dart' as impl;

/// Barra lateral de anuncio de AdSense para el diseño de escritorio de la
/// versión web. En Android (o si por lo que sea no se resuelve la
/// implementación web) no muestra nada.
Widget buildAdsenseSidebar() => impl.buildAdsenseSidebar();
