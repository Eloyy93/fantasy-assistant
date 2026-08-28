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

/// Ajusta un campo (u otro widget con relación de aspecto fija) para que
/// quepa ENTERO en el espacio disponible, tanto a lo ancho como a lo alto
/// — a diferencia de [AspectRatio] a secas, que en un contenedor con altura
/// libre (ej. dentro de un ListView) siempre ocupa todo el ancho aunque
/// eso dé una altura mayor que la pantalla, obligando a desplazarse para
/// ver el campo completo. Necesita estar dentro de algo con altura
/// acotada (ej. un Expanded en un Column no scrolleable).
class FitAspectRatio extends StatelessWidget {
  final double aspectRatio;
  final Widget child;

  const FitAspectRatio({super.key, required this.aspectRatio, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var width = constraints.maxWidth;
        var height = width / aspectRatio;
        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * aspectRatio;
        }
        return Center(
          child: SizedBox(width: width, height: height, child: child),
        );
      },
    );
  }
}
