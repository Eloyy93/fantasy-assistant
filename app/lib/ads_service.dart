import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Ad unit IDs — de PRUEBA (oficiales de Google: sirven anuncios reales de
/// muestra, sin infringir política, y sin necesitar cuenta de AdMob).
/// Sustituir por los IDs reales de vuestra cuenta de AdMob antes de
/// publicar en Play Store — si no, Google puede suspender la cuenta por
/// tráfico inválido (anuncios de prueba mostrados a usuarios reales).
const String _testBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

/// TODO al crear la cuenta de AdMob: registrar la app ahí, crear un bloque
/// de anuncios "Banner" y sustituir _testBannerAdUnitId (y el App ID en
/// AndroidManifest.xml) por los reales.
String get bannerAdUnitId => _testBannerAdUnitId;

Future<void> initAds() async {
  await MobileAds.instance.initialize();
}

/// Banner de 320x50 anclado donde se coloque, con su propio ciclo de vida
/// (se carga al montar, se libera al desmontar). No se muestra nada mientras
/// carga ni si falla — evita un hueco en blanco parpadeante.
class BannerAdBar extends StatefulWidget {
  const BannerAdBar({super.key});

  @override
  State<BannerAdBar> createState() => _BannerAdBarState();
}

class _BannerAdBarState extends State<BannerAdBar> {
  BannerAd? _ad;
  bool _cargado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    final ad = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _cargado = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cargado || _ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
