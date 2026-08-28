// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

const String _adClient = 'ca-pub-2987330970119801';

// TODO: crea un bloque de anuncios "Display" en AdSense (Anuncios > Por
// bloque de anuncios > Crear bloque de anuncios) y sustituye este slot de
// ejemplo por el ID real — hasta entonces el hueco se reserva pero
// AdSense no sirve nada ahí.
const String _adSlot = '0000000000';

const String _viewType = 'adsense-sidebar';
bool _registrado = false;

/// Anuncio de AdSense en la barra lateral de escritorio, montado como
/// elemento HTML real (vía HtmlElementView). Un <ins class="adsbygoogle">
/// insertado dinámicamente después de cargar la página necesita su propio
/// push() a la cola de AdSense — el escaneo inicial del script no lo
/// detecta solo. Se hace con un <script> creado y añadido por DOM (SÍ se
/// ejecuta, a diferencia de uno metido por innerHTML) en vez de JS interop,
/// para no depender de una API que puede cambiar entre versiones de Dart.
Widget buildAdsenseSidebar() {
  if (!_registrado) {
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final contenedor = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%';

      final ins = html.Element.tag('ins')
        ..className = 'adsbygoogle'
        ..style.display = 'block'
        ..setAttribute('data-ad-client', _adClient)
        ..setAttribute('data-ad-slot', _adSlot)
        ..setAttribute('data-ad-format', 'auto')
        ..setAttribute('data-full-width-responsive', 'true');
      contenedor.append(ins);

      final script = html.ScriptElement()..text = '(adsbygoogle = window.adsbygoogle || []).push({});';
      contenedor.append(script);

      return contenedor;
    });
    _registrado = true;
  }

  return const SizedBox(width: 300, child: HtmlElementView(viewType: _viewType));
}
