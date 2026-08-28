import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Product ID de la suscripción mensual "sin anuncios". Hay que crear un
/// producto de suscripción con EXACTAMENTE este ID en Play Console
/// (Monetización > Productos > Suscripciones) antes de que la compra
/// funcione — hasta entonces, queryProductDetails no lo encuentra y el
/// botón de suscribirse se deshabilita solo con un aviso.
const String noAdsProductId = 'master_fantasy_no_ads_monthly';

const _prefsKeyAdsRemoved = 'ads_removed';

/// Gestiona la compra/restauración de la suscripción "sin anuncios" y
/// expone si están quitados como un ValueNotifier para que la UI reaccione
/// al momento (el banner desaparece nada más completarse la compra).
///
/// Nota sobre verificación: el estado se guarda localmente al recibir una
/// compra que Google Play ya validó en el propio flujo de compra
/// (purchased/restored) — suficiente para un proyecto de este tamaño, pero
/// no a prueba de manipulación (un dispositivo rooteado podría falsificar
/// el flag local guardado). Blindarlo del todo requeriría validar el
/// recibo contra la Google Play Developer API desde el backend — no
/// implementado; queda como TODO si esto se convierte en algo serio.
class PurchaseService {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  final ValueNotifier<bool> adsRemoved = ValueNotifier(false);
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  List<ProductDetails> _productos = [];
  String? error;

  List<ProductDetails> get productos => _productos;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    adsRemoved.value = prefs.getBool(_prefsKeyAdsRemoved) ?? false;

    // in_app_purchase es solo Android/iOS — en la versión web no hay
    // tienda con la que hablar (ni sentido: los anuncios ya no se
    // muestran ahí, ver ads_service.dart).
    if (kIsWeb) return;

    final disponible = await InAppPurchase.instance.isAvailable();
    if (!disponible) {
      error = 'Las compras no están disponibles en este dispositivo.';
      return;
    }

    _sub = _iap.purchaseStream.listen(_onPurchaseUpdate, onError: (_) {});

    try {
      final respuesta = await _iap.queryProductDetails({noAdsProductId});
      _productos = respuesta.productDetails;
      if (respuesta.notFoundIDs.isNotEmpty) {
        error = 'La suscripción todavía no está configurada en Play Console.';
      }
    } catch (e) {
      error = 'No se pudo consultar la suscripción: $e';
    }
  }

  Future<void> disposeService() async {
    await _sub?.cancel();
  }

  Future<void> comprar() async {
    if (_productos.isEmpty) return;
    final param = PurchaseParam(productDetails: _productos.first);
    // Las suscripciones también se compran con buyNonConsumable en este
    // paquete — la distinción consumible/no-consumible solo afecta a si
    // hay que llamar a consumePurchase después, y una suscripción nunca se
    // consume.
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restaurar() async {
    await _iap.restorePurchases();
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> compras) async {
    for (final compra in compras) {
      if (compra.status == PurchaseStatus.purchased || compra.status == PurchaseStatus.restored) {
        await _marcarSinAnuncios(true);
      }
      if (compra.pendingCompletePurchase) {
        await _iap.completePurchase(compra);
      }
    }
  }

  Future<void> _marcarSinAnuncios(bool valor) async {
    adsRemoved.value = valor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyAdsRemoved, valor);
  }
}
