import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// ID del bloque de anuncios "Banner" real, de la cuenta de AdMob
/// vinculada a la app publicada en Play Store (ver también el App ID en
/// AndroidManifest.xml).
const String _bannerAdUnitId = 'ca-app-pub-2987330970119801/3711591786';

String get bannerAdUnitId => _bannerAdUnitId;

Future<void> initAds() async {
  // google_mobile_ads no tiene implementación web — en la versión web no
  // se muestran anuncios (ver BannerAdBar más abajo).
  if (kIsWeb) return;
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
    if (kIsWeb) return;
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
