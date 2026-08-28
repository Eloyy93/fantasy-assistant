// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
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
      // Ancho fijo en píxeles (no "100%") — el div del HtmlElementView
      // puede no tener todavía el tamaño real que le da Flutter en el
      // primer frame, y AdSense calcula el hueco del anuncio nada más
      // insertarlo: con "100%" sin padre medido aún, ve un ancho de 0 y
      // el push() falla ("No slot size for availableWidth=0").
      final contenedor = html.DivElement()
        ..style.width = '300px'
        ..style.height = '100%';

      final ins = html.Element.tag('ins')
        ..className = 'adsbygoogle'
        ..style.display = 'block'
        ..style.width = '300px'
        ..setAttribute('data-ad-client', _adClient)
        ..setAttribute('data-ad-slot', _adSlot)
        ..setAttribute('data-ad-format', 'auto');
      contenedor.append(ins);

      final script = html.ScriptElement()..text = '(adsbygoogle = window.adsbygoogle || []).push({});';
      // Un pequeño margen para que el navegador termine de aplicar el
      // layout del platform view antes de que AdSense mida el hueco.
      Timer(const Duration(milliseconds: 300), () => contenedor.append(script));

      return contenedor;
    });
    _registrado = true;
  }

  return const SizedBox(width: 300, child: HtmlElementView(viewType: _viewType));
}
