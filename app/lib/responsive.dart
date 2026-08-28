import 'package:flutter/material.dart';

/// A partir de este ancho la app deja de tratarse como "móvil estirado" y
/// pasa a diseño de escritorio (contenido centrado, listas en cuadrícula,
/// hueco para el anuncio lateral).
const double kDesktopBreakpoint = 900;

bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

/// Centra el contenido con un ancho máximo cómodo de leer en pantallas
/// anchas — en móvil no hace nada (child tal cual). Sin esto, en escritorio
/// la app se ve como la versión móvil simplemente estirada de borde a
/// borde.
class DesktopContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const DesktopContainer({super.key, required this.child, this.maxWidth = 760});

  @override
  Widget build(BuildContext context) {
    if (!isDesktop(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}
