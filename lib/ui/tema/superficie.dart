// Reemplazo de `Bloque` (ya borrado, 2026-10-03) — puerto de
// `lib/companion/tema/superficie.dart`: más redondeado, con un modo de
// relleno sólido o degradé ("color-blocking") para las piezas que tienen
// que saltar a la vista (el total de Venta, el resumen del día).
//
// "Lenguaje de diseño" (El dueño, 2026-09-26): la tarjeta vuelve a ser plana —
// relleno opaco, sin borde, sin sombra, sin el brillo de "vidrio" del
// rediseño del 2026-09-25. La jerarquía la da el salto de color contra el
// canvas (#F0F4F9 → blanco), como en los mocks. `resplandor` queda en la
// API para no tocar a los llamadores, pero ya no pinta nada (ver
// `resplandor.dart`).

import 'package:flutter/material.dart';

import 'tema.dart';
import 'tokens.dart';

class Superficie extends StatelessWidget {
  const Superficie({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Espaciado.lg),
    this.relleno,
    this.degrade,
    this.colorTexto,
    this.resplandor = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// No nulo = "color-blocking": la superficie entera se pinta con este
  /// color sólido en vez del gris translúcido de `fondoBloque` — para la
  /// pieza que más importa de una pantalla.
  final Color? relleno;

  /// Alternativa a [relleno]: dos o más colores en diagonal, para las
  /// piezas "hero" de la app. Gana sobre [relleno] si los dos están puestos.
  final List<Color>? degrade;

  /// Color de texto sugerido para cuando `relleno`/`degrade` está puesto (el
  /// llamador decide si lo usa — este widget no fuerza el color de sus
  /// hijos).
  final Color? colorTexto;

  /// Halo neón — solo tiene efecto con `relleno`/`degrade` puesto (una
  /// superficie gris no tiene de qué color brillar). Reservado para las
  /// piezas "hero" de cada pantalla.
  final bool resplandor;

  @override
  Widget build(BuildContext context) {
    final gradiente = degrade;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radioSuperficieEscritorio),
        color: gradiente == null ? (relleno ?? context.colores.fondoBloque) : null,
        gradient: gradiente == null
            ? null
            : LinearGradient(colors: gradiente, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: child,
    );
  }
}
